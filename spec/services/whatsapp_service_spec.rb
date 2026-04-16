require "rails_helper"

RSpec.describe WhatsappService do
  include ActiveSupport::Testing::TimeHelpers

  let(:service) { described_class.new }
  let(:ai_service) { double("AiService") }

  before do
    # Stub AI service
    allow(AiService).to receive(:new).and_return(ai_service)
    allow(ai_service).to receive(:process_message)

    # Stub WhatsappTemplateService to not require Twilio creds
    allow(WhatsappTemplateService).to receive(:new).and_raise(StandardError)
  end

  describe "#handle_incoming" do
    context "with a new patient" do
      it "creates a patient and conversation, and processes through AI for multi-turn support" do
        allow(ai_service).to receive(:process_message).and_return({
          response: "I'd love to help you book an appointment. What date works best for you?",
          intent: "book",
          entities: {}
        })

        result = service.handle_incoming(
          from: "+27611111111",
          message: "I want to book an appointment"
        )

        expect(result[:response]).to include("book an appointment")
        expect(result[:intent]).to eq("book")
        expect(ai_service).to have_received(:process_message)

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
          # No date/time yet — the AI is still gathering preferences,
          # so attempt_booking is intentionally not invoked here.
          entities: {}
        })

        result = service.handle_incoming(
          from: "+27622222222",
          message: "Monday at 10am please"
        )

        expect(result[:response]).to include("availability")
        expect(patient.conversations.count).to eq(1) # reused, not new
      end
    end

    context "when booking with valid date/time and available slot" do
      let!(:patient) { create(:patient, phone: "+27699999999") }

      it "creates a local Appointment and the booking shows on calendar" do
        # Thursday 2026-04-16, wday=4 — need a DoctorSchedule for Thursday
        create(:doctor_schedule, day_of_week: 4)

        # Stub Google Calendar so it doesn't fail the test
        allow(GoogleCalendarService).to receive(:new).and_raise(StandardError, "no creds")

        # Freeze time to Wed 2026-04-15 so Thursday is in the future
        travel_to Time.zone.parse("2026-04-15 10:00") do
          allow(ai_service).to receive(:process_message).and_return({
            response: "Perfect! I have you booked for Thursday at 9am.",
            intent: "book",
            entities: { date: "2026-04-16", time: "09:00", treatment: "consultation" }
          })

          result = service.handle_incoming(from: "+27699999999", message: "Book me Thursday 9am")

          # The booking succeeded locally, so the AI's response stands
          expect(result[:response]).to include("booked")

          appointment = Appointment.find_by(patient: patient)
          expect(appointment).to be_present
          expect(appointment.start_time).to eq(Time.zone.parse("2026-04-16 09:00"))
          expect(appointment.end_time).to eq(Time.zone.parse("2026-04-16 09:30"))
          expect(appointment.reason).to eq("Consultation")
          expect(appointment.status).to eq("scheduled")
        end
      end
    end

    context "when the slot conflicts with an existing appointment" do
      let!(:patient) { create(:patient, phone: "+27699999998") }

      it "rewrites the response with the booking-failed fallback" do
        create(:doctor_schedule, day_of_week: 4)

        travel_to Time.zone.parse("2026-04-15 10:00") do
          # An existing appointment occupies 09:00–09:30 on Thursday
          create(:appointment,
            patient: create(:patient, phone: "+27600000001"),
            start_time: Time.zone.parse("2026-04-16 09:00"),
            end_time: Time.zone.parse("2026-04-16 09:30"),
            status: :scheduled
          )

          allow(ai_service).to receive(:process_message).and_return({
            response: "Perfect! I have you booked for Thursday at 9am.",
            intent: "book",
            entities: { date: "2026-04-16", time: "09:00", treatment: "consultation" }
          })

          result = service.handle_incoming(from: "+27699999998", message: "Book me Thursday 9am")

          expect(result[:response]).to eq(WhatsappService::BOOKING_FAILED_FALLBACK["en"])
          expect(Appointment.where(patient: patient).count).to eq(0)
        end
      end
    end

    context "when booking outside working hours" do
      let!(:patient) { create(:patient, phone: "+27699999997") }

      it "rewrites the response with the booking-failed fallback" do
        # Sunday is closed (no active schedule)
        create(:doctor_schedule, :closed, day_of_week: 0)

        travel_to Time.zone.parse("2026-04-15 10:00") do
          allow(ai_service).to receive(:process_message).and_return({
            response: "Perfect! I have you booked for Sunday at 10am.",
            intent: "book",
            entities: { date: "2026-04-19", time: "10:00", treatment: "consultation" }
          })

          result = service.handle_incoming(from: "+27699999997", message: "Book me Sunday 10am")

          expect(result[:response]).to eq(WhatsappService::BOOKING_FAILED_FALLBACK["en"])
          expect(Appointment.where(patient: patient).count).to eq(0)
        end
      end
    end

    context "when the AI claims a booking but never extracted a date/time" do
      let!(:patient) { create(:patient, phone: "+27688888888") }

      it "rewrites the optimistic AI reply with an honest fallback" do
        # The classifier failed to normalize a relative date like
        # "Friday at 11am" into ISO format, so entities are empty —
        # but the response generator still hallucinated a confirmation.
        # This is the most common real-world lying-bot path.
        allow(ai_service).to receive(:process_message).and_return({
          response: "Perfect! I have you booked for Friday at 11am.",
          intent: "book",
          entities: {}
        })

        result = service.handle_incoming(from: "+27688888888", message: "Book me Friday 11am")

        expect(result[:response]).to eq(WhatsappService::BOOKING_FAILED_FALLBACK["en"])
        expect(Appointment.where(patient: patient).count).to eq(0)
      end

      it "leaves a genuine clarifying reply alone" do
        # Multi-turn gathering: AI is still asking for preferences and
        # is NOT claiming a booking. We must not rewrite this.
        allow(ai_service).to receive(:process_message).and_return({
          response: "Sure! What day and time works best for you?",
          intent: "book",
          entities: {}
        })

        result = service.handle_incoming(from: "+27688888889", message: "I'd like to book")

        expect(result[:response]).to include("What day")
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
      it "processes FAQ questions through AI for natural multi-turn conversations" do
        allow(ai_service).to receive(:process_message).and_return({
          response: "We're open Monday to Friday 8am–5pm. We're closed on weekends.",
          intent: "faq",
          entities: {}
        })

        result = service.handle_incoming(
          from: "+27644444444",
          message: "What are your hours?"
        )

        expect(result[:response]).to include("Monday to Friday")
        expect(result[:intent]).to eq("faq")
        expect(ai_service).to have_received(:process_message)
      end
    end

    context "when the AI provider is temporarily unavailable" do
      it "returns a helpful fallback response and stores it in the conversation" do
        allow(ai_service).to receive(:process_message)
          .and_raise(AiService::Error, "Response generation failed: the server responded with status 529")

        result = service.handle_incoming(
          from: "+27655555555",
          message: "I want to book an appointment"
        )

        expect(result[:intent]).to eq("book")
        expect(result[:response]).to include("preferred day and time")

        patient = Patient.find_by(phone: "+27655555555")
        conversation = patient.conversations.order(:created_at).last

        expect(conversation.messages.length).to eq(2)
        expect(conversation.messages.first["role"]).to eq("user")
        expect(conversation.messages.last["role"]).to eq("assistant")
        expect(conversation.messages.last["content"]).to include("preferred day and time")
      end

      it "answers office hours locally when AI is unavailable" do
        allow(ai_service).to receive(:process_message)
          .and_raise(AiService::Error, "Intent classification failed: the server responded with status 529")

        result = service.handle_incoming(
          from: "+27655555556",
          message: "What are your hours?"
        )

        expect(result[:intent]).to eq("faq")
        expect(result[:response]).to include("We're open")
      end

      it "answers pricing locally when AI is unavailable" do
        allow(ai_service).to receive(:process_message)
          .and_raise(AiService::Error, "Intent classification failed: the server responded with status 529")

        result = service.handle_incoming(
          from: "+27655555557",
          message: "How much is a consultation?"
        )

        expect(result[:intent]).to eq("faq")
        expect(result[:response]).to include(AiService::PRICING["consultation"])
      end
    end
  end
end
