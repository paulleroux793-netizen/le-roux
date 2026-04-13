require "rails_helper"

RSpec.describe WhatsappTemplateService do
  let(:patient) { create(:patient, first_name: "Dee", last_name: "Botha", phone: "+27612345678") }
  let(:appointment) { create(:appointment, patient: patient, start_time: Time.zone.parse("2026-04-20 10:00"), end_time: Time.zone.parse("2026-04-20 10:30")) }
  let(:twilio_client) { double("Twilio::REST::Client") }
  let(:messages) { double("messages") }

  before do
    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
    allow(twilio_client).to receive(:messages).and_return(messages)
    allow(messages).to receive(:create).and_return(double("message", sid: "SM123"))

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("TWILIO_ACCOUNT_SID").and_return("test_sid")
    allow(ENV).to receive(:fetch).with("TWILIO_AUTH_TOKEN").and_return("test_token")
    allow(ENV).to receive(:fetch).with("TWILIO_WHATSAPP_NUMBER").and_return("+14155238886")
    allow(ENV).to receive(:fetch).with("WHATSAPP_TPL_CONFIRMATION", "").and_return("HX_confirmation")
    allow(ENV).to receive(:fetch).with("WHATSAPP_TPL_REMINDER_24H", "").and_return("HX_reminder_24h")
    allow(ENV).to receive(:fetch).with("WHATSAPP_TPL_REMINDER_1H", "").and_return("HX_reminder_1h")
    allow(ENV).to receive(:fetch).with("WHATSAPP_TPL_CANCELLATION", "").and_return("HX_cancellation")
    allow(ENV).to receive(:fetch).with("WHATSAPP_TPL_RESCHEDULE", "").and_return("HX_reschedule")
    allow(ENV).to receive(:fetch).with("WHATSAPP_TPL_FLAGGED_ALERT", "").and_return("HX_flagged")
    allow(ENV).to receive(:fetch).with("RECEPTION_WHATSAPP_NUMBER", anything).and_return("+27600000000")
  end

  let(:service) { described_class.new }

  describe "#send_confirmation" do
    it "sends confirmation template with correct variables" do
      service.send_confirmation(patient, appointment)

      expect(messages).to have_received(:create).with(hash_including(
        content_sid: "HX_confirmation",
        to: "whatsapp:+27612345678"
      ))
    end
  end

  describe "#send_reminder_24h" do
    it "sends 24h reminder template" do
      service.send_reminder_24h(patient, appointment)

      expect(messages).to have_received(:create).with(hash_including(
        content_sid: "HX_reminder_24h"
      ))
    end
  end

  describe "#send_reminder_1h" do
    it "sends 1h reminder template" do
      service.send_reminder_1h(patient, appointment)

      expect(messages).to have_received(:create).with(hash_including(
        content_sid: "HX_reminder_1h"
      ))
    end
  end

  describe "#send_cancellation" do
    it "sends cancellation template" do
      service.send_cancellation(patient, appointment)

      expect(messages).to have_received(:create).with(hash_including(
        content_sid: "HX_cancellation"
      ))
    end
  end

  describe "#send_reschedule" do
    it "sends reschedule template" do
      service.send_reschedule(patient, appointment)

      expect(messages).to have_received(:create).with(hash_including(
        content_sid: "HX_reschedule"
      ))
    end
  end

  describe "#send_flagged_alert" do
    it "sends flagged alert to reception" do
      service.send_flagged_alert(patient, "No answer after 3 attempts")

      expect(messages).to have_received(:create).with(hash_including(
        content_sid: "HX_flagged",
        to: "whatsapp:+27600000000"
      ))
    end
  end
end
