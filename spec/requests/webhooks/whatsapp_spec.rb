require "rails_helper"

RSpec.describe "Webhooks::Whatsapp", type: :request do
  let(:ai_service) { double("AiService") }

  before do
    allow(AiService).to receive(:new).and_return(ai_service)
    allow(ai_service).to receive(:process_message).and_return({
      response: "Hi! How can I help you today?",
      intent: "other",
      entities: {}
    })

    # Stub template service to not require Twilio creds
    allow(WhatsappTemplateService).to receive(:new).and_raise(StandardError)
  end

  describe "POST /webhooks/whatsapp" do
    let(:valid_params) do
      {
        "From" => "whatsapp:+27612345678",
        "Body" => "Hello, I want to book",
        "To" => "whatsapp:+14155238886",
        "MessageSid" => "SM_test_123"
      }
    end

    it "returns 200 with TwiML response" do
      post "/webhooks/whatsapp", params: valid_params

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/xml")
      expect(response.body).to include("<Response>")
      expect(response.body).to include("<Message>")
    end

    it "creates a patient from the incoming number" do
      expect {
        post "/webhooks/whatsapp", params: valid_params
      }.to change(Patient, :count).by(1)

      patient = Patient.last
      expect(patient.phone).to eq("+27612345678")
    end

    it "creates a conversation" do
      expect {
        post "/webhooks/whatsapp", params: valid_params
      }.to change(Conversation, :count).by(1)

      conversation = Conversation.last
      expect(conversation.channel).to eq("whatsapp")
      expect(conversation.status).to eq("active")
    end

    it "returns bad request when From is missing" do
      post "/webhooks/whatsapp", params: { "Body" => "Hello" }
      expect(response).to have_http_status(:bad_request)
    end

    it "returns bad request when Body is missing" do
      post "/webhooks/whatsapp", params: { "From" => "whatsapp:+27612345678" }
      expect(response).to have_http_status(:bad_request)
    end

    it "handles button payload from quick replies" do
      params = valid_params.merge("ButtonPayload" => "confirm", "Body" => "")
      post "/webhooks/whatsapp", params: params

      expect(response).to have_http_status(:ok)
    end

    it "includes the AI response in the TwiML" do
      post "/webhooks/whatsapp", params: valid_params

      expect(response.body).to include("How can I help you today?")
    end

    context "when an error occurs" do
      before do
        allow(ai_service).to receive(:process_message).and_raise(StandardError, "Something broke")
      end

      it "returns a friendly error message" do
        post "/webhooks/whatsapp", params: valid_params

        expect(response).to have_http_status(:ok) # Still OK — TwiML response
        expect(response.body).to include("something went wrong")
      end
    end
  end
end
