require "rails_helper"

# Proves the web chat widget books through the SAME brain + guards as WhatsApp:
# - reuses AiService (channel: :web) for the conversation
# - books only via the shared BookingEngine (no weekend / no after-hours / no double-book)
# - POPIA-gates booking behind a WhatsApp number + consent
RSpec.describe WebChatService do
  let(:ai) { instance_double(AiService) }
  subject(:service) { described_class.new(ai_service: ai) }

  around { |ex| travel_to(Time.zone.parse("2026-06-15 11:00")) { ex.run } } # Monday 11:00
  before do
    (1..5).each { |d| create(:doctor_schedule, day_of_week: d) }              # open Mon–Fri (effective 10:00–19:00 in tests)
    allow(WhatsappPackSender).to receive(:call).and_return({ sent: 4, failed: 0, skipped: false }) # never hit Twilio
  end

  def stub_ai(intent:, entities:, response: "ok")
    allow(ai).to receive(:process_message).and_return(response: response, intent: intent, entities: entities)
  end

  describe "#handle_message — booking via the web channel" do
    it "books a valid slot once a WhatsApp number + consent are given" do
      stub_ai(intent: "book", entities: { date: "2026-06-17", time: "11:00", treatment: "consultation" })
      r = service.handle_message(session_id: "s1", message: "book me", visitor_name: "Jane Doe",
                                 visitor_phone: "+27821234567", consent: true)
      expect(r[:booked]).to be true
      expect(Appointment.find(r[:appointment_id]).start_time).to eq(Time.zone.parse("2026-06-17 11:00"))
      expect(r[:reply]).to include("WhatsApp")
    end

    it "GUARD: refuses a weekend — no appointment created" do
      stub_ai(intent: "book", entities: { date: "2026-06-20", time: "11:00" }) # Saturday
      r = service.handle_message(session_id: "s2", message: "book sat", visitor_phone: "+27821234567", consent: true)
      expect(r[:booked]).to be false
      expect(Appointment.count).to eq(0)
      expect(r[:reply]).to match(/closed|Monday to Friday|weekend/i)
    end

    it "GUARD: refuses an after-hours time — no appointment created" do
      stub_ai(intent: "book", entities: { date: "2026-06-17", time: "20:00" })
      r = service.handle_message(session_id: "s3", message: "book late", visitor_phone: "+27821234567", consent: true)
      expect(r[:booked]).to be false
      expect(Appointment.count).to eq(0)
    end

    it "GUARD: refuses a double-booking of a taken slot" do
      create(:patient).appointments.create!(start_time: Time.zone.parse("2026-06-17 12:00"),
                                             end_time: Time.zone.parse("2026-06-17 12:30"),
                                             reason: "Existing", status: :scheduled)
      stub_ai(intent: "book", entities: { date: "2026-06-17", time: "12:00", treatment: "consultation" })
      r = service.handle_message(session_id: "s4", message: "book noon", visitor_phone: "+27821234999", consent: true)
      expect(r[:booked]).to be false
      expect(r[:reply]).to match(/taken|available/i)
    end

    it "sends the WhatsApp pack (directions/address/intake/details) after a successful booking" do
      stub_ai(intent: "book", entities: { date: "2026-06-17", time: "13:00", treatment: "consultation" })
      expect(WhatsappPackSender).to receive(:call).with(an_instance_of(Appointment)).and_return({ sent: 4 })
      service.handle_message(session_id: "p1", message: "book me", visitor_name: "Jane Doe",
                             visitor_phone: "+27821234567", consent: true)
    end

    it "does NOT send the WhatsApp pack when a booking is refused (weekend)" do
      stub_ai(intent: "book", entities: { date: "2026-06-20", time: "11:00" }) # Saturday
      expect(WhatsappPackSender).not_to receive(:call)
      service.handle_message(session_id: "p2", message: "book sat", visitor_phone: "+27821234567", consent: true)
    end

    it "POPIA GATE: does not book until WhatsApp number + consent are given" do
      stub_ai(intent: "book", entities: { date: "2026-06-17", time: "11:00", treatment: "consultation" })
      r = service.handle_message(session_id: "s5", message: "book me")
      expect(r[:booked]).to be false
      expect(r[:needs_contact]).to be true
      expect(Appointment.count).to eq(0)
    end
  end

  it "routes the conversation through the SAME AiService brain on channel :web with session memory" do
    stub_ai(intent: "faq", entities: {})
    expect(ai).to receive(:process_message)
      .with(hash_including(channel: :web, conversation: instance_of(WebChatSession)))
      .and_return(response: "We do offer whitening!", intent: "faq", entities: {})
    out = service.handle_message(session_id: "s6", message: "do you do whitening?")
    expect(out[:reply]).to eq("We do offer whitening!")
  end
end
