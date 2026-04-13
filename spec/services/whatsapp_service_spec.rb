require "rails_helper"

RSpec.describe WhatsappService do
  let(:service) { described_class.new }
  let(:ai_service) { double("AiService") }
  let(:messages_api) { double("messages_api") }

  before do
    # Stub AI service
    allow(AiService).to receive(:new).and_return(ai_service)

    # Stub Anthropic client for AiService initialization
    client = double("Anthropic::Client", messages: messages_api)
    allow(Anthropic::Client).to receive(:new).and_return(client)

    # Stub WhatsappTemplateService to not require Twilio creds
    allow(WhatsappTemplateService).to receive(:new).and_raise(StandardError)
  end

  describe "#handle_incoming" do
    context "with a new patient" do
      it "creates a patient and conversation, returns AI response" do
        allow(ai_service).to receive(:process_message).and_return({
          response: "Hi there! I'd love to help you book an appointment. What day works best?",
          intent: "book",
          entities: { date: nil, time: nil }
        })

        result = service.handle_incoming(
          from: "+27611111111",
          message: "I want to book an appointment"
        )

        expect(result[:response]).to include("book an appointment")
        expect(result[:intent]).to eq("book")

        patient = Patient.find_by(phone: "+27611111111")
        expect(patient).to be_present
        expect(patient.conversations.count).to eq(1)
      end
    end

    context "with an existing patient" do
      let!(:patient) { create(:patient, phone: "+27622222222") }

      it "reuses existing patient and active conversation" do
        conversation = create(:conversation, patient: patient, channel: "whatsapp", status: "active")

        allow(ai_service).to receive(:process_message).and_return({
          response: "Sure, let me check availability!",
          intent: "book",
          entities: { date: "2026-04-20", time: "10:00" }
        })

        result = service.handle_incoming(
          from: "+27622222222",
          message: "Monday at 10am please"
        )

        expect(result[:response]).to include("availability")
        expect(patient.conversations.count).to eq(1) # reused, not new
      end
    end

    context "with a confirmation intent" do
      let!(:patient) { create(:patient, phone: "+27633333333") }

      it "confirms a scheduled appointment for today" do
        appointment = create(:appointment,
          patient: patient,
          start_time: Time.current + 2.hours,
          end_time: Time.current + 2.5.hours,
          status: :scheduled
        )

        allow(ai_service).to receive(:process_message).and_return({
          response: "Great, your appointment is confirmed!",
          intent: "confirm",
          entities: {}
        })

        service.handle_incoming(from: "+27633333333", message: "Confirm")

        appointment.reload
        expect(appointment.status).to eq("confirmed")
        expect(appointment.confirmation_logs.count).to eq(1)
        expect(appointment.confirmation_logs.first.outcome).to eq("confirmed")
      end
    end

    context "with an FAQ intent" do
      it "returns AI response without side effects" do
        allow(ai_service).to receive(:process_message).and_return({
          response: "We're open Monday to Friday 8am-5pm!",
          intent: "faq",
          entities: {}
        })

        result = service.handle_incoming(
          from: "+27644444444",
          message: "What are your hours?"
        )

        expect(result[:response]).to include("Monday to Friday")
        expect(result[:intent]).to eq("faq")
      end
    end
  end
end
