FactoryBot.define do
  factory :appointment do
    patient
    sequence(:start_time) { |n| 1.day.from_now.change(hour: 10, min: 0) + (n * 35).minutes }
    end_time { start_time + 30.minutes }
    status { :scheduled }
    reason { "General consultation" }
    notes { nil }

    trait :confirmed do
      status { :confirmed }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :with_google_event do
      sequence(:google_event_id) { |n| "google_event_#{n}" }
    end

    trait :past do
      start_time { 1.day.ago.change(hour: 10) }
      end_time   { 1.day.ago.change(hour: 10, min: 30) }

      to_create { |instance| instance.save!(validate: false) }
    end
  end
end
