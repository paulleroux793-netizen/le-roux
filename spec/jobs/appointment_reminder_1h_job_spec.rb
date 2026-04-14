require "rails_helper"

RSpec.describe AppointmentReminder1hJob, type: :job do
  let(:template_service) { instance_double(WhatsappTemplateService) }

  before do
    allow(WhatsappTemplateService).to receive(:new).and_return(template_service)
    allow(template_service).to receive(:send_reminder_1h)
  end

  it "is queued on the default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  describe "#perform" do
    let(:patient) { create(:patient) }

    context "with an appointment in the 45–75 minute window" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: 60.minutes.from_now,
          end_time:   90.minutes.from_now,
          status:     :scheduled
        )
      end

      it "sends a 1h reminder" do
        described_class.perform_now

        expect(template_service).to have_received(:send_reminder_1h).with(patient, appointment)
      end
    end

    context "with a confirmed appointment in the window" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: 50.minutes.from_now,
          end_time:   80.minutes.from_now,
          status:     :confirmed
        )
      end

      it "sends a reminder for confirmed appointments" do
        described_class.perform_now

        expect(template_service).to have_received(:send_reminder_1h).with(patient, appointment)
      end
    end

    context "with an appointment starting in 2 hours (outside window)" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: 2.hours.from_now,
          end_time:   2.hours.from_now + 30.minutes,
          status:     :scheduled
        )
      end

      it "skips appointments outside the window" do
        described_class.perform_now

        expect(template_service).not_to have_received(:send_reminder_1h)
      end
    end

    context "with an appointment starting in 10 minutes (inside window lower bound: 45 min)" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: 10.minutes.from_now,
          end_time:   40.minutes.from_now,
          status:     :scheduled
        )
      end

      it "skips appointments starting too soon" do
        described_class.perform_now

        expect(template_service).not_to have_received(:send_reminder_1h)
      end
    end

    context "with a cancelled appointment in the window" do
      let!(:appointment) do
        create(:appointment,
          patient:    patient,
          start_time: 60.minutes.from_now,
          end_time:   90.minutes.from_now,
          status:     :cancelled
        )
      end

      it "skips cancelled appointments" do
        described_class.perform_now

        expect(template_service).not_to have_received(:send_reminder_1h)
      end
    end

    context "when a reminder fails for one appointment" do
      let(:patient2) { create(:patient) }
      let!(:appt1) do
        create(:appointment,
          patient:    patient,
          start_time: 50.minutes.from_now,
          end_time:   80.minutes.from_now,
          status:     :scheduled
        )
      end
      let!(:appt2) do
        create(:appointment,
          patient:    patient2,
          start_time: 65.minutes.from_now,
          end_time:   95.minutes.from_now,
          status:     :scheduled
        )
      end

      before do
        call_count = 0
        allow(template_service).to receive(:send_reminder_1h) do
          call_count += 1
          raise WhatsappTemplateService::Error, "Send failed" if call_count == 1
        end
      end

      it "continues sending reminders for remaining appointments" do
        expect { described_class.perform_now }.not_to raise_error

        expect(template_service).to have_received(:send_reminder_1h).twice
      end
    end
  end
end
