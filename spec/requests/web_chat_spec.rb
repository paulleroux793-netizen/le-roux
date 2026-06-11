require "rails_helper"

# The public web-chat endpoint: flip-switch OFF by default, returns a reply when ON.
RSpec.describe "Web chat API", type: :request do
  around do |ex|
    original = ENV["WEB_CHAT_ENABLED"]
    ex.run
    ENV["WEB_CHAT_ENABLED"] = original
  end

  before do
    allow_any_instance_of(AiService).to receive(:process_message)
      .and_return(response: "Hi! I can book you in — what day suits you?", intent: "faq", entities: {})
  end

  it "returns a reply JSON when WEB_CHAT_ENABLED is on" do
    ENV["WEB_CHAT_ENABLED"] = "true"
    post "/api/v1/web_chat", params: { session_id: "abc-123", message: "do you do whitening?" }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["reply"]).to include("book you in")
    expect(body["session_id"]).to eq("abc-123")
    expect(body["booked"]).to eq(false)
  end

  it "is OFF by default — returns 404 when the flag is unset (flip-switch)" do
    ENV["WEB_CHAT_ENABLED"] = nil
    post "/api/v1/web_chat", params: { session_id: "abc-123", message: "hi" }
    expect(response).to have_http_status(:not_found)
  end
end
