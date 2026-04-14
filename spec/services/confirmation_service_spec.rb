require "rails_helper"

RSpec.describe ConfirmationService do
  let(:twilio_client)    { instance_double(Twilio::REST::Client) }
  let(:twilio_calls)     { instance_double(Twilio::REST::Api::V2010::AccountContext::CallList) }
  let(:template_service) { instance_double(WhatsappTemplateService) }

  before do
    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
    allow(twilio_client).to receive(:calls).and_return(twilio_calls)
    allow(WhatsappTemplateService).to receive(:new).and_return(template_service)
    stub_const("ENV", ENV.to_h.merge(
      "APP_BASE_URL"       => "https://test.ngrok.io",
      "TWILIO_PHONE_NUMBER" => "+14155551234"
    ))
  end

  let(:service) { described_class.new }

  # ── run_daily_confirmations ───────────────────────────────────────────

  describe "#run_daily_confirmations" do
    let(:patient)     { create(:patient) }
    let!(:today_appt) do
      create(:appointment,
        patient:    patient,
        start_time: Time.current.change(hour: 10),
        end_time:   Time.current.change(hour: 10, min: 30),
        status:     :scheduled
      )
    end

    context "when the call is placed successfully" do
      before do
        allow(twilio_calls).to receive(:create).and_return(double("call", sid: "CA_test"))
        allow(template_service).to receive(:send_confirmation)
      end

      it "places one outbound call per unconfirmed appointment" do
        service.run_daily_confirmations

        expect(twilio_calls).to have_received(:create).once
      end

      it "creates a ConfirmationLog with method: voice and attempts: 1" do
        service.run_daily_confirmations

        log = today_appt.confirmation_logs.last
        expect(log.method).to eq("voice")
        expect(log.attempts).to eq(1)
        expect(log.flagged).to be(false)
      end

      it "does not send a WhatsApp fallback when the call succeeds" do
        service.run_daily_confirmations

        expect(template_service).not_to have_received(:send_confirmation)
      end
    end

    context "when the appointment is already confirmed" do
      before do
        today_appt.update!(status: :confirmed)
        allow(twilio_calls).to receive(:create)
      end

      it "skips the confirmed appointment" do
        service.run_daily_confirmations

        expect(twilio_calls).not_to have_received(:create)
      end
    end

    context "when the appointment is for a different day" do
      before do
        today_appt.update!(
          start_time: 1.day.from_now.change(hour: 10),
          end_time:   1.day.from_now.change(hour: 10, min: 30)
        )
        allow(twilio_calls).to receive(:create)
      end

      it "skips the future appointment" do
        service.run_daily_confirmations

        expect(twilio_calls).not_to have_received(:create)
      end
    end

    context "when the call fails (Twilio API error)" do
      before do
        allow(twilio_calls).to receive(:create)
          .and_raise(Twilio::REST::TwilioError.new("Invalid number"))
        allow(template_service).to receive(:send_confirmation)
      end

      it "falls back to a WhatsApp confirmation" do
        service.run_daily_confirmations

        expect(template_service).to have_received(:send_confirmation).with(patient, today_appt)
      end

      it "updates the confirmation log method to whatsapp" do
        service.run_daily_confirmations

        log = today_appt.confirmation_logs.last
        expect(log.method).to eq("whatsapp")
      end
    end

    context "when both call and WhatsApp fail" do
      before do
        allow(twilio_calls).to receive(:create)
          .and_raise(Twilio::REST::TwilioError.new("Invalid number"))
        allow(template_service).to receive(:send_confirmation)
          .and_raise(WhatsappTemplateService::Error, "Not configured")
        allow(template_service).to receive(:send_flagged_alert)
      end

      it "flags the confirmation log for manual review" do
        service.run_daily_confirmations

        log = today_appt.confirmation_logs.last
        expect(log.flagged).to be(true)
        expect(log.outcome).to eq("no_answer")
      end

      it "sends a flagged alert to reception" do
        service.run_daily_confirmations

        expect(template_service).to have_received(:send_flagged_alert).with(patient, anything)
      end
    end

    context "when a system error occurs for one appointment" do
      let!(:second_appt) do
        create(:appointment,
          patient:    create(:patient),
          start_time: Time.current.change(hour: 11),
          end_time:   Time.current.change(hour: 11, min: 30),
          status:     :scheduled
        )
      end

      before do
        call_count = 0
        allow(twilio_calls).to receive(:create) do
          call_count += 1
          raise StandardError, "Unexpected error" if call_count == 1

          double("call", sid: "CA_second")
        end
        allow(template_service).to receive(:send_flagged_alert)
      end

      it "continues processing the remaining appointments" do
        expect { service.run_daily_confirmations }.not_to raise_error

        # The second appointment should still have been attempted
        expect(second_appt.confirmation_logs.count).to eq(1)
      end
    end
  end
end
