class SettingsController < ApplicationController
  SUPPORTED_LANGUAGES = %w[en af].freeze

  # POST /settings/language
  # Persists the dashboard UI language to session.
  # Falls back to "en" for any unknown value.
  def update_language
    lang = params[:language].to_s.downcase
    session[:ui_language] = SUPPORTED_LANGUAGES.include?(lang) ? lang : "en"
    head :no_content
  end

  def index
    page_data = dev_page_cache("settings", "index") do
      {
        schedules: DoctorSchedule.order(:day_of_week).map { |s|
          {
            id: s.id,
            day_name: s.day_name,
            day_of_week: s.day_of_week,
            start_time: s.start_time&.strftime("%H:%M"),
            end_time: s.end_time&.strftime("%H:%M"),
            break_start: s.break_start&.strftime("%H:%M"),
            break_end: s.break_end&.strftime("%H:%M"),
            active: s.active
          }
        },
        pricing: AiService::PRICING,
        practice: {
          name: "Dr Chalita le Roux Inc",
          address: "Unit 2, Amorosa Office Park",
          address_line2: "Corner of Doreen Road, Lawrence Rd",
          city: "Amorosa, Johannesburg, 2040",
          phone: ENV.fetch("TWILIO_WHATSAPP_NUMBER", "+27 XX XXX XXXX"),
          email: ENV.fetch("MAILER_FROM_ADDRESS", "reception@drchalitaleroux.co.za"),
          map_link: WhatsappService::PRACTICE_MAP_LINK
        },
        notifications: {
          email_confirmations: true,
          email_reminders: true,
          sms_confirmations: ENV["TWILIO_SMS_NUMBER"].present?,
          sms_reminders: ENV["TWILIO_SMS_NUMBER"].present?,
          whatsapp_confirmations: true,
          whatsapp_reminders: true,
          reminder_hours_before: 24
        }
      }
    end

    render inertia: "Settings", props: page_data
  end
end
