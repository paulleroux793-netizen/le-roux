require "rails_helper"

RSpec.describe AppointmentReminder24hJob, type: :job do
  let(:template_service) { instance_double(WhatsappTemplateService) }

  before do
    allow(WhatsappTemplateService).to receive(:new).and_return(template_service)
    allow(template_service).to receive(:send_confirmation_request_with_buttons)
    # Stub mailer and SMS to avoid external calls
    allow(AppointmentMailer).to receive_message_chain(:reminder, :deliver_later)
    allow(SmsService).to receive(:send_reminder)
  end

  it "is queued on the default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  describe "#perform" do
    let(:patient) { create(:patient) }

    context "with a scheduled appointment tomorrow" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: Date.tomorrow.to_time.change(hour: 10),
          end_time:   Date.tomorrow.to_time.change(hour: 10, min: 30),
          status:     :scheduled
        )
      end

      it "sends a 24h reminder for the appointment" do
        described_class.perform_now

        expect(template_service).to have_received(:send_confirmation_request_with_buttons).with(patient, appointment)
      end
    end

    context "with a confirmed appointment tomorrow" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: Date.tomorrow.to_time.change(hour: 14),
          end_time:   Date.tomorrow.to_time.change(hour: 14, min: 30),
          status:     :confirmed
        )
      end

      it "sends a reminder for confirmed appointments too" do
        described_class.perform_now

        expect(template_service).to have_received(:send_confirmation_request_with_buttons).with(patient, appointment)
      end
    end

    context "with a cancelled appointment tomorrow" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: Date.tomorrow.to_time.change(hour: 9),
          end_time:   Date.tomorrow.to_time.change(hour: 9, min: 30),
          status:     :cancelled
        )
      end

      it "skips cancelled appointments" do
        described_class.perform_now

        expect(template_service).not_to have_received(:send_confirmation_request_with_buttons)
      end
    end

    context "with an appointment today (not tomorrow)" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: Time.current.change(hour: 15),
          end_time:   Time.current.change(hour: 15, min: 30),
          status:     :scheduled
        )
      end

      it "skips today's appointments" do
        described_class.perform_now

        expect(template_service).not_to have_received(:send_confirmation_request_with_buttons)
      end
    end

    context "when the template service raises an error for one appointment" do
      let(:patient2) { create(:patient) }
      let!(:appt1) do
        create(:appointment,
          patient:    patient,
          start_time: Date.tomorrow.to_time.change(hour: 9),
          end_time:   Date.tomorrow.to_time.change(hour: 9, min: 30),
          status:     :scheduled
        )
      end
      let!(:appt2) do
        create(:appointment,
          patient:    patient2,
          start_time: Date.tomorrow.to_time.change(hour: 10),
          end_time:   Date.tomorrow.to_time.change(hour: 10, min: 30),
          status:     :scheduled
        )
      end

      before do
        call_count = 0
        allow(template_service).to receive(:send_confirmation_request_with_buttons) do
          call_count += 1
          raise WhatsappTemplateService::Error, "Send failed" if call_count == 1
        end
      end

      it "continues sending reminders for remaining appointments" do
        expect { described_class.perform_now }.not_to raise_error

        expect(template_service).to have_received(:send_confirmation_request_with_buttons).twice
      end
    end
  end
end
