require "rails_helper"

RSpec.describe MorningConfirmationJob, type: :job do
  let(:confirmation_service) { instance_double(ConfirmationService) }

  before do
    allow(ConfirmationService).to receive(:new).and_return(confirmation_service)
    allow(confirmation_service).to receive(:run_daily_confirmations)
  end

  it "delegates to ConfirmationService#run_daily_confirmations" do
    described_class.perform_now

    expect(confirmation_service).to have_received(:run_daily_confirmations)
  end

  it "is queued on the default queue" do
    expect(described_class.queue_name).to eq("default")
  end
end
