class SettingsController < ApplicationController
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
        pricing: AiService::PRICING
      }
    end

    render inertia: "Settings", props: page_data
  end
end
