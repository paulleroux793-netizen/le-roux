require "rails_helper"

RSpec.describe GoogleCalendarService do
  let(:service) { described_class.new }
  let(:patient) { create(:patient) }
  let(:monday) { Date.new(2026, 4, 20) } # A Monday

  before do
    # Stub Google API authorization
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds)
      .and_return(double("credentials"))

    # Stub the CalendarService to not make real calls
    allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
      .to receive(:authorization=)

    # Default stub for freebusy - individual tests can override
    empty_response = double("freebusy_response",
      calendars: { GoogleCalendarService::CALENDAR_ID => double(busy: []) }
    )
    allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
      .to receive(:query_freebusy).and_return(empty_response)

    # Set timezone for consistent test results
    Time.zone = "Africa/Johannesburg"

    # Create doctor schedule for Monday (8am-5pm, lunch 12-1pm)
    create(:doctor_schedule,
      day_of_week: 1,
      start_time: Time.parse("08:00"),
      end_time: Time.parse("17:00"),
      break_start: Time.parse("12:00"),
      break_end: Time.parse("13:00"),
      active: true
    )
  end

  describe "#available_slots" do
    it "returns empty array when doctor is not working that day" do
      # Create a closed schedule for Sunday explicitly
      create(:doctor_schedule, :closed, day_of_week: 0)
      sunday = Date.new(2026, 4, 19)
      expect(service.available_slots(sunday)).to eq([])
    end

    it "returns 30-minute slots excluding breaks and busy periods" do
      busy_response = double("freebusy_response",
        calendars: { GoogleCalendarService::CALENDAR_ID => double(busy: []) }
      )
      allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
        .to receive(:query_freebusy).and_return(busy_response)

      slots = service.available_slots(monday)

      # 8am-12pm = 8 slots, 1pm-5pm = 8 slots = 16 total
      expect(slots.length).to eq(16)
      first_start = slots.first[:start_time]
      expect(first_start.strftime("%H:%M")).to eq("08:00")
      last_end = slots.last[:end_time]
      expect(last_end.strftime("%H:%M")).to eq("17:00")
    end

    it "excludes slots that overlap with busy periods" do
      zone = Time.find_zone("Africa/Johannesburg")
      busy_period = double(
        start: zone.parse("2026-04-20 09:00"),
        end: zone.parse("2026-04-20 10:00")
      )
      busy_response = double("freebusy_response",
        calendars: { GoogleCalendarService::CALENDAR_ID => double(busy: [ busy_period ]) }
      )
      allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
        .to receive(:query_freebusy).and_return(busy_response)

      slots = service.available_slots(monday)

      slot_starts = slots.map { |s| s[:start_time].strftime("%H:%M") }
      expect(slot_starts).not_to include("09:00", "09:30")
      expect(slot_starts).to include("08:00", "08:30", "10:00")
    end
  end

  describe "#book_appointment" do
    it "creates a Google Calendar event and local appointment" do
      google_event = double("event", id: "gcal_event_123")
      allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
        .to receive(:insert_event).and_return(google_event)

      start_time = Time.zone.parse("2026-04-20 10:00")
      appointment = service.book_appointment(
        patient: patient,
        start_time: start_time,
        reason: "Consultation"
      )

      expect(appointment).to be_persisted
      expect(appointment.google_event_id).to eq("gcal_event_123")
      expect(appointment.patient).to eq(patient)
      expect(appointment.reason).to eq("Consultation")
      expect(appointment.status).to eq("scheduled")
    end
  end

  describe "#find_appointment" do
    it "returns upcoming appointments for a patient" do
      appointment = create(:appointment, patient: patient, start_time: 2.days.from_now, end_time: 2.days.from_now + 30.minutes)
      results = service.find_appointment(patient.phone)
      expect(results).to include(appointment)
    end

    it "raises NotFoundError for unknown phone" do
      expect { service.find_appointment("+27000000000") }
        .to raise_error(GoogleCalendarService::NotFoundError)
    end
  end

  describe "#reschedule_appointment" do
    it "updates both Google Calendar and local appointment" do
      appointment = create(:appointment, patient: patient, google_event_id: "gcal_123",
        start_time: 2.days.from_now, end_time: 2.days.from_now + 30.minutes)

      google_event = double("event", start: nil, end: nil)
      allow(google_event).to receive(:start=)
      allow(google_event).to receive(:end=)

      allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
        .to receive(:get_event).and_return(google_event)
      allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
        .to receive(:update_event).and_return(google_event)

      new_start = 3.days.from_now
      result = service.reschedule_appointment("gcal_123", new_start: new_start)

      expect(result.status).to eq("rescheduled")
      expect(result.start_time).to be_within(1.second).of(new_start)
    end
  end

  describe "#cancel_appointment" do
    it "deletes Google event and cancels local appointment" do
      appointment = create(:appointment, patient: patient, google_event_id: "gcal_456",
        start_time: 2.days.from_now, end_time: 2.days.from_now + 30.minutes)

      allow_any_instance_of(Google::Apis::CalendarV3::CalendarService)
        .to receive(:delete_event)

      result = service.cancel_appointment("gcal_456", reason_category: "cost", reason_details: "Too expensive")

      expect(result.status).to eq("cancelled")
      expect(result.cancellation_reason.reason_category).to eq("cost")
    end
  end
end
