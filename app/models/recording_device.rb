# N1 — A physical microphone/recorder placed somewhere in the practice.
# The always-on scribe routes audio to the correct ScribeSession based
# on which device captured it. Admin-only management screen at
# /admin/recording_devices.
class RecordingDevice < ApplicationRecord
  LOCATIONS = %w[surgery_1 surgery_2 reception waiting_area sterilisation other].freeze

  has_many :scribe_sessions, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :location, inclusion: { in: LOCATIONS }

  scope :enabled, -> { where(enabled: true) }
  scope :for_location, ->(loc) { where(location: loc) }

  # Recommended canonical 3-device boot config for a single-dentist
  # practice. Seed-able; admin can rename/add later.
  DEFAULT_LAYOUT = [
    { name: "Surgery 1", location: "surgery_1" },
    { name: "Reception", location: "reception" }
  ].freeze
end
