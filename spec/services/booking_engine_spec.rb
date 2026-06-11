require "rails_helper"

# Proves the SHARED booking core enforces the three hard guards Paul requires —
# no weekends, no after-hours, no double-booking — plus the booking buffer.
# This is the core that both the WhatsApp bot and the web chat widget book through.
RSpec.describe BookingEngine do
  let(:patient) { create(:patient) }

  around do |ex|
    travel_to(Time.zone.parse("2026-06-15 08:00")) { ex.run } # a Monday, 08:00
  end

  before do
    (1..5).each { |d| create(:doctor_schedule, day_of_week: d) } # open Mon–Fri
  end

  it "books a valid future weekday slot" do
    # NB: 2026-06-16 is Youth Day (SA public holiday) — use the 17th, a clear Wednesday.
    # The doctor_schedule factory's effective hours are 10:00–19:00 with a 14:00–15:00 break,
    # so 11:00 is a clean in-hours slot. (The engine enforces whatever DoctorSchedule says.)
    r = described_class.call(patient: patient, date: "2026-06-17", time: "11:00", treatment: "consultation")
    expect(r.status).to eq(:booked)
    expect(r.appointment).to be_persisted
    expect(r.appointment.start_time).to eq(Time.zone.parse("2026-06-17 11:00"))
  end

  it "GUARD: rejects a Saturday (no weekends)" do
    r = described_class.call(patient: patient, date: "2026-06-20", time: "09:00") # Saturday
    expect(r.status).to eq(:public_holiday)
    expect(Appointment.count).to eq(0)
  end

  it "GUARD: rejects an after-hours time (no after-hours)" do
    r = described_class.call(patient: patient, date: "2026-06-17", time: "19:00")
    expect(r.status).to eq(:outside_working_hours)
    expect(Appointment.count).to eq(0)
  end

  it "GUARD: rejects a double-booking of a taken slot" do
    described_class.call(patient: create(:patient), date: "2026-06-18", time: "10:00", treatment: "consultation")
    r = described_class.call(patient: patient, date: "2026-06-18", time: "10:00", treatment: "consultation")
    expect(r.status).to eq(:slot_taken)
  end

  it "rejects a slot inside the booking buffer as too_soon" do
    r = described_class.call(patient: patient, date: "2026-06-15", time: "08:10")
    expect(r.status).to eq(:too_soon)
  end
end
