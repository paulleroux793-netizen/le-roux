require "rails_helper"

RSpec.describe IntakeDispatch do
  let(:patient) { create(:patient, first_name: "Naledi", last_name: "Dube", phone: "+27821112222") }
  let(:twilio_client) { double("Twilio::REST::Client") }
  let(:messages) { double("messages") }
  let(:sent) { [] }

  before do
    seed_intake_templates!

    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
    allow(twilio_client).to receive(:messages).and_return(messages)
    allow(messages).to receive(:create) { |**kwargs| sent << kwargs; double("message", sid: "SM1") }

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("TWILIO_ACCOUNT_SID").and_return("sid")
    allow(ENV).to receive(:fetch).with("TWILIO_AUTH_TOKEN").and_return("token")
    allow(ENV).to receive(:fetch).with("TWILIO_WHATSAPP_NUMBER").and_return("+14155238886")
    allow(ENV).to receive(:fetch).with("BASE_URL").and_return("https://ivory.example.com")
  end

  it "creates one pending submission per intake template" do
    expect { described_class.call(patient) }
      .to change { patient.form_submissions.count }.by(IntakeProcessor::KEYS.size)

    expect(patient.form_submissions.pluck(:status).uniq).to eq(["sent"])
  end

  it "sends a WhatsApp message containing the tokenised intake link" do
    link = described_class.call(patient)

    expect(link).to start_with("https://ivory.example.com/intake/")
    expect(messages).to have_received(:create).once
    body = sent.first[:body]
    expect(body).to include(link)
    expect(body).to include(patient.first_name)
  end

  it "produces a link that resolves back to the patient" do
    link = described_class.call(patient)
    token = link.split("/intake/").last
    expect(Patient.find_signed(token, purpose: :intake)).to eq(patient)
  end

  it "raises a friendly error when the patient has no phone" do
    patient.update_column(:phone, nil)
    expect { described_class.call(patient) }.to raise_error(IntakeDispatch::Error, /no WhatsApp number/)
  end

  it "raises when the templates are not seeded" do
    FormTemplate.update_all(active: false)
    expect { described_class.call(patient) }.to raise_error(IntakeDispatch::Error, /not seeded/)
  end
end
