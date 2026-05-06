require "yaml"

# Loads the single source of truth for practice data from
# config/practice_config.yml. Every value the AI quotes (prices, addresses,
# services, FAQ entries, banking details, wording) goes through here — no
# more scattered constants in AiService / WhatsappService / SmsService /
# PromptBuilder. Edit the YAML; the AI sees the change on next deploy.
#
# Code-locked behavioural guardrails (no past bookings, idempotency,
# false-confirmation rewrite, etc.) are NOT in here — they stay in code.
# This service holds facts and wording; the guardrails consume them.
class PracticeConfig
  CONFIG_PATH = Rails.root.join("config", "practice_config.yml").freeze

  class << self
    # Memoize per Rails process. Reload! is exposed for tests.
    def instance
      @instance ||= new
    end

    def reload!
      @instance = nil
      instance
    end

    # Convenience delegators for the most-used sections so callers don't
    # need to chain .data.dig everywhere.
    %i[
      practice address working_hours public_holidays services
      default_appointment_duration_minutes banking payment faq
      pricing_guidance emergency_policy after_hours_behaviour
      format_rules personality greetings reception_takeover
      confirmations_and_reminders
    ].each do |key|
      define_method(key) { instance.public_send(key) }
    end

    # Service lookup helpers used by booking + prompt code.
    def service(key)         = instance.service(key)
    def whitening            = instance.whitening
    def aliases_for(key)     = instance.aliases_for(key)
    def duration_for(treatment) = instance.duration_for(treatment)
    def public_holiday?(date)   = instance.public_holiday?(date)
    def full_address            = instance.full_address
    def map_link                = instance.map_link
    def directions              = instance.directions
    def medical_aid_policy      = instance.medical_aid_policy
    def booking_buffer_minutes  = instance.booking_buffer_minutes
    def ai_pause_hours          = instance.ai_pause_hours
  end

  attr_reader :data

  def initialize(path = CONFIG_PATH)
    @data = YAML.load_file(path).deep_symbolize_keys.freeze
    validate!
  rescue Errno::ENOENT
    raise "PracticeConfig: file not found at #{path}"
  rescue Psych::SyntaxError => e
    raise "PracticeConfig: YAML syntax error in #{path}: #{e.message}"
  end

  # Top-level section accessors.
  def practice                          = @data[:practice]
  def address                           = @data[:address]
  def working_hours                     = @data[:working_hours]
  def public_holidays                   = @data[:public_holidays]
  def services                          = @data[:services]
  def default_appointment_duration_minutes = @data[:default_appointment_duration_minutes]
  def banking                           = @data[:banking]
  def payment                           = @data[:payment]
  def faq                               = @data[:faq]
  def pricing_guidance                  = @data[:pricing_guidance]
  def emergency_policy                  = @data[:emergency_policy]
  def after_hours_behaviour             = @data[:after_hours_behaviour]
  def format_rules                      = @data[:format_rules]
  def personality                       = @data[:personality]
  def greetings                         = @data[:greetings]
  def reception_takeover                = @data[:reception_takeover]
  def confirmations_and_reminders       = @data[:confirmations_and_reminders]

  # ── Service lookup ────────────────────────────────────────────────────

  def service(key)
    services.find { |s| s[:key].to_s == key.to_s }
  end

  def whitening
    service(:whitening)
  end

  def aliases_for(key)
    Array(service(key)&.dig(:aliases)).map(&:to_s)
  end

  # Resolve a free-text treatment label (from the AI's entity extraction)
  # to an appointment duration in minutes. Falls back to the default.
  def duration_for(treatment)
    return default_appointment_duration_minutes if treatment.blank?

    label = treatment.to_s.downcase.strip
    matched = services.find do |s|
      [s[:key].to_s, s[:name].to_s.downcase, *Array(s[:aliases]).map(&:downcase)].include?(label)
    end
    matched&.dig(:duration_minutes) || default_appointment_duration_minutes
  end

  # ── Date / hours helpers ──────────────────────────────────────────────

  def public_holiday?(date)
    return false unless date
    iso = date.respond_to?(:iso8601) ? date.iso8601 : date.to_s
    public_holidays.any? { |h| h[:date].to_s == iso }
  end

  def public_holiday_dates
    @public_holiday_dates ||= public_holidays.map { |h| Date.parse(h[:date].to_s) }.freeze
  end

  # ── Address / contact convenience ─────────────────────────────────────

  def full_address
    [address[:line1], address[:line2], address[:city]].compact.join(", ")
  end

  def map_link    = address[:map_link]
  def directions  = address[:directions]
  def parking     = address[:parking]

  # ── Wording convenience ───────────────────────────────────────────────

  def medical_aid_policy = payment[:medical_aid_policy].to_s.strip

  # ── Policy values ─────────────────────────────────────────────────────

  def booking_buffer_minutes = format_rules[:booking_buffer_minutes].to_i
  def ai_pause_hours         = reception_takeover[:ai_pause_hours].to_i

  private

  # Catch obvious errors at boot rather than at first patient interaction.
  def validate!
    %i[practice address working_hours public_holidays services greetings].each do |required|
      unless @data.key?(required)
        raise "PracticeConfig: required section missing — #{required}"
      end
    end

    if booking_buffer_minutes <= 0
      raise "PracticeConfig: format_rules.booking_buffer_minutes must be > 0"
    end

    if services.empty? || services.none? { |s| s[:key].to_s == "consultation" }
      raise "PracticeConfig: services must include at least 'consultation'"
    end
  end
end
