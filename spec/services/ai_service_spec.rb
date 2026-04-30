require "rails_helper"

RSpec.describe AiService do
  let(:patient) { create(:patient, first_name: "Sarah", last_name: "Botha") }
  let(:client) { double("Anthropic::Client") }

  before do
    allow(Anthropic::Client).to receive(:new).and_return(client)
  end

  let(:service) { described_class.new }

  before do
    allow(service).to receive(:sleep)
  end

  def mock_claude_response(text)
    { "content" => [ { "type" => "text", "text" => text } ] }
  end

  describe "#classify_intent" do
    it "classifies a booking request" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response('{"intent": "book", "entities": {"date": "2026-04-20", "time": "10:00", "name": "Sarah", "treatment": "consultation"}}'))

      result = service.classify_intent("I'd like to book a consultation for Monday at 10am")

      expect(result[:intent]).to eq("book")
      expect(result[:entities][:date]).to eq("2026-04-20")
      expect(result[:entities][:treatment]).to eq("consultation")
    end

    it "classifies a cancellation request" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response('{"intent": "cancel", "entities": {"date": null, "time": null, "name": null, "treatment": null}}'))

      result = service.classify_intent("I need to cancel my appointment")
      expect(result[:intent]).to eq("cancel")
    end

    it "classifies an FAQ question" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response('{"intent": "faq", "entities": {"date": null, "time": null, "name": null, "treatment": null}}'))

      result = service.classify_intent("What are your office hours?")
      expect(result[:intent]).to eq("faq")
    end

    it "returns 'other' for unparseable responses" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response("I'm not sure what to make of that"))

      result = service.classify_intent("asdfghjkl")
      expect(result[:intent]).to eq("other")
    end

    it "fails fast on Anthropic overload errors" do
      error = Faraday::ServerError.new("overloaded", { status: 529 })
      allow(client).to receive(:messages).and_raise(error)

      expect {
        service.classify_intent("I want to book")
      }.to raise_error(AiService::Error, /Intent classification failed/)

      expect(client).to have_received(:messages).once
    end

    it "wraps persistent Anthropic overload errors" do
      error = Faraday::ServerError.new("overloaded", { status: 529 })
      allow(client).to receive(:messages).and_raise(error)

      expect {
        service.classify_intent("I want to book")
      }.to raise_error(AiService::Error, /Intent classification failed/)
    end
  end

  describe "#generate_response" do
    it "generates a conversational response" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response("Hi Sarah! I'd love to help you book an appointment. What day works best for you?"))

      response = service.generate_response(
        message: "Hi, I'd like to see the dentist",
        patient: patient
      )

      expect(response).to include("Sarah")
      expect(response).to include("appointment")
    end

    it "includes conversation history for context" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response("Sure! How about Tuesday at 2pm?"))

      service.generate_response(
        message: "How about next week?",
        conversation_history: [
          { role: "user", content: "I want to book" },
          { role: "assistant", content: "What day works for you?" }
        ]
      )

      expect(client).to have_received(:messages).once
    end
  end

  describe "#extract_entities" do
    it "extracts date, time, name, and treatment" do
      allow(client).to receive(:messages)
        .and_return(mock_claude_response('{"date": "2026-04-20", "time": "14:00", "name": "Sarah Botha", "treatment": "cleaning", "phone": null}'))

      result = service.extract_entities("I'm Sarah Botha, I'd like a cleaning next Monday at 2pm")

      expect(result[:date]).to eq("2026-04-20")
      expect(result[:time]).to eq("14:00")
      expect(result[:name]).to eq("Sarah Botha")
      expect(result[:treatment]).to eq("cleaning")
    end
  end

  describe "#process_message" do
    it "classifies intent and generates a response" do
      allow(client).to receive(:messages)
        .and_return(
          mock_claude_response('{"intent": "book", "entities": {"date": "2026-04-20", "time": "10:00", "name": null, "treatment": "consultation"}}'),
          mock_claude_response("Great! Let me check availability for Monday at 10am.")
        )

      result = service.process_message(message: "Book me for Monday 10am consultation", patient: patient)

      expect(result[:intent]).to eq("book")
      expect(result[:response]).to include("Monday")
    end

    it "stores messages in conversation when provided" do
      conversation = create(:conversation, patient: patient)

      allow(client).to receive(:messages)
        .and_return(
          mock_claude_response('{"intent": "faq", "entities": {"date": null, "time": null, "name": null, "treatment": null}}'),
          mock_claude_response("We're open Monday to Friday 8am-5pm!")
        )

      service.process_message(message: "What are your hours?", conversation: conversation, patient: patient)

      conversation.reload
      expect(conversation.messages.length).to eq(2)
      expect(conversation.messages.first["role"]).to eq("user")
      expect(conversation.messages.last["role"]).to eq("assistant")
    end
  end

  describe "PRICING" do
    it "knows consultation and cleaning prices" do
      expect(AiService::PRICING["consultation"]).to eq("approximately R850 (may include X-rays, excludes 2D/3D scans)")
      expect(AiService::PRICING["cleaning"]).to eq("approximately R1,500")
    end
  end

  describe "FAQ" do
    it "has answers for common questions" do
      expect(AiService::FAQ.keys).to include("hours", "location", "services", "payment")
    end

    it "includes the reception-derived FAQ entries (walk-ins, costs, sedation, aftercare, family)" do
      expect(AiService::FAQ.keys).to include(
        "walk_ins",
        "consultation_cost",
        "filling_cost",
        "extraction_cost",
        "surgical_extraction",
        "sedation_kids",
        "aftercare_eating",
        "family_booking"
      )
    end

    it "walk_ins answer offers an alternative instead of refusing" do
      expect(AiService::FAQ.fetch("walk_ins")).to include("don't accept walk-ins")
      expect(AiService::FAQ.fetch("walk_ins")).to include("same-day or next-day")
    end

    it "extraction_cost answer mentions both the standard price AND the surgical caveat" do
      txt = AiService::FAQ.fetch("extraction_cost")
      expect(txt).to include("R1,900")
      expect(txt).to include("oral surgeon")
      expect(txt).to include("don't perform surgical extractions")
    end

    it "surgical_extraction answer refuses + refers out (defense in depth with prompt rule)" do
      txt = AiService::FAQ.fetch("surgical_extraction")
      expect(txt).to include("don't perform surgical extractions in-house")
      expect(txt).to include("oral surgeon")
    end

    it "consultation_cost answer states approximate R850 with caveats" do
      txt = AiService::FAQ.fetch("consultation_cost")
      expect(txt).to include("R850")
      expect(txt).to include("excludes 2D/3D scans")
    end

    it "aftercare_eating answer reassures the patient + warns about numb lip/cheek" do
      txt = AiService::FAQ.fetch("aftercare_eating")
      expect(txt).to include("light-cured")
      expect(txt).to include("numb")
    end

    it "FAQ remains frozen after additions" do
      expect(AiService::FAQ).to be_frozen
    end
  end
end
