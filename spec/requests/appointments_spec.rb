require 'rails_helper'
require 'inertia_rails/rspec'

RSpec.describe 'Appointments', type: :request do
  describe 'GET /appointments' do
    it 'scopes calendar appointments to the requested visible range' do
      in_range = create(:appointment,
        start_time: Time.zone.local(2026, 5, 12, 9, 0),
        end_time: Time.zone.local(2026, 5, 12, 9, 30)
      )
      out_of_range = create(:appointment,
        start_time: Time.zone.local(2026, 6, 2, 9, 0),
        end_time: Time.zone.local(2026, 6, 2, 9, 30)
      )

      get appointments_path, params: {
        calendar_start: '2026-05-11T00:00:00+02:00',
        calendar_end: '2026-05-18T00:00:00+02:00',
        calendar_date: '2026-05-12',
        calendar_view: 'timeGridWeek'
      }

      expect(response).to have_http_status(:ok)
      ids = inertia.props[:calendar_appointments].map { |appointment| appointment[:id] }
      expect(ids).to include(in_range.id)
      expect(ids).not_to include(out_of_range.id)
      expect(inertia.props[:calendar_meta]).to include(
        initial_date: '2026-05-12',
        view: 'timeGridWeek'
      )
    end
  end

  describe 'PATCH /appointments/:id' do
    let!(:appointment) { create(:appointment) }
    let(:new_start) { 3.days.from_now.change(hour: 14, min: 0) }
    let(:new_end)   { 3.days.from_now.change(hour: 14, min: 30) }

    it 'reschedules a local appointment' do
      patch appointment_path(appointment), params: {
        appointment: {
          start_time: new_start.iso8601,
          end_time: new_end.iso8601
        }
      }

      expect(response).to have_http_status(:see_other)
      expect(response.headers['Location']).to include("calendar_date=#{new_start.to_date.iso8601}")
      appointment.reload
      expect(appointment.start_time).to be_within(1.second).of(new_start)
      expect(appointment.end_time).to be_within(1.second).of(new_end)
    end

    it 'updates reason and notes without touching time' do
      original_start = appointment.start_time
      patch appointment_path(appointment), params: {
        appointment: { reason: 'Root canal', notes: 'Anxious patient' }
      }

      expect(response).to have_http_status(:see_other)
      appointment.reload
      expect(appointment.reason).to eq('Root canal')
      expect(appointment.notes).to eq('Anxious patient')
      expect(appointment.start_time).to be_within(1.second).of(original_start)
    end

    it 'rejects invalid times' do
      patch appointment_path(appointment),
        params: {
          appointment: { start_time: 'not-a-date', end_time: '' }
        },
        headers: { 'X-Inertia' => 'true', 'X-Requested-With' => 'XMLHttpRequest' }

      expect(response).to have_http_status(:see_other)
      expect(session[:inertia_errors]).to include(start_time: 'Invalid start or end time')
    end

    it 'rejects end_time <= start_time' do
      patch appointment_path(appointment),
        params: {
          appointment: {
            start_time: new_start.iso8601,
            end_time: new_start.iso8601
          }
        },
        headers: { 'X-Inertia' => 'true', 'X-Requested-With' => 'XMLHttpRequest' }

      expect(response).to have_http_status(:see_other)
      expect(session[:inertia_errors]).to include(end_time: 'End time must be after start time')
    end

    context 'when the appointment is linked to a Google Calendar event' do
      let!(:appointment) { create(:appointment, :with_google_event) }

      it 'syncs via GoogleCalendarService' do
        fake_service = instance_double(GoogleCalendarService)
        allow(GoogleCalendarService).to receive(:new).and_return(fake_service)
        expect(fake_service).to receive(:reschedule_appointment)
          .with(appointment.google_event_id, new_start: kind_of(ActiveSupport::TimeWithZone), new_end: kind_of(ActiveSupport::TimeWithZone))

        patch appointment_path(appointment), params: {
          appointment: {
            start_time: new_start.iso8601,
            end_time: new_end.iso8601
          }
        }

        expect(response).to have_http_status(:see_other)
      end

      it 'still persists locally when Google sync raises' do
        fake_service = instance_double(GoogleCalendarService)
        allow(GoogleCalendarService).to receive(:new).and_return(fake_service)
        allow(fake_service).to receive(:reschedule_appointment).and_raise(StandardError, 'boom')

        expect(Rails.logger).to receive(:error).with(/Google sync failed/)

        patch appointment_path(appointment), params: {
          appointment: {
            start_time: new_start.iso8601,
            end_time: new_end.iso8601
          }
        }

        expect(response).to have_http_status(:see_other)
        appointment.reload
        expect(appointment.start_time).to be_within(1.second).of(new_start)
      end
    end
  end

  describe 'POST /appointments' do
    let!(:patient) { create(:patient) }
    let(:start_at) { 5.days.from_now.change(hour: 9, min: 0) }
    let(:end_at)   { 5.days.from_now.change(hour: 9, min: 30) }

    before do
      # Force the local-only branch for these specs — we don't want to
      # hit the Google Calendar service here; it's covered by its own
      # spec in spec/services.
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_CALENDAR_ID").and_return(nil)
    end

    it 'creates a local appointment' do
      expect {
        post appointments_path, params: {
          appointment: {
            patient_id: patient.id,
            start_time: start_at.iso8601,
            end_time: end_at.iso8601,
            reason: 'Cleaning'
          }
        }
      }.to change(Appointment, :count).by(1)

      expect(response).to have_http_status(:see_other)
      expect(response.headers['Location']).to include("calendar_date=#{start_at.to_date.iso8601}")
      appointment = Appointment.last
      expect(appointment.patient).to eq(patient)
      expect(appointment.reason).to eq('Cleaning')
      expect(appointment.status).to eq('scheduled')
    end

    it 'parses browser UTC ISO timestamps back into the clinic timezone' do
      start_payload = '2026-05-14T07:00:00.000Z'
      end_payload = '2026-05-14T07:30:00.000Z'

      post appointments_path, params: {
        appointment: {
          patient_id: patient.id,
          start_time: start_payload,
          end_time: end_payload,
          reason: 'Consultation'
        }
      }

      appointment = Appointment.last
      expect(appointment.start_time.in_time_zone.strftime('%Y-%m-%d %H:%M')).to eq('2026-05-14 09:00')
      expect(appointment.end_time.in_time_zone.strftime('%Y-%m-%d %H:%M')).to eq('2026-05-14 09:30')
    end

    it 'rejects invalid times without creating anything' do
      expect {
        post appointments_path, params: {
          appointment: {
            patient_id: patient.id,
            start_time: '',
            end_time: ''
          }
        }, headers: { 'X-Inertia' => 'true', 'X-Requested-With' => 'XMLHttpRequest' }
      }.not_to change(Appointment, :count)

      expect(response).to have_http_status(:see_other)
      expect(session[:inertia_errors]).to include(start_time: 'Invalid start or end time')
    end

    it 'rejects bookings with a start_time in the past' do
      expect {
        post appointments_path, params: {
          appointment: {
            patient_id: patient.id,
            start_time: 2.hours.ago.iso8601,
            end_time: 1.hour.ago.iso8601,
            reason: 'Cleaning'
          }
        }, headers: { 'X-Inertia' => 'true', 'X-Requested-With' => 'XMLHttpRequest' }
      }.not_to change(Appointment, :count)

      expect(response).to have_http_status(:see_other)
      expect(session[:inertia_errors]).to include(start_time: 'must be in the future')
    end
  end

  describe 'PATCH /appointments/:id/cancel' do
    let!(:appointment) { create(:appointment) }

    it 'marks the appointment as cancelled' do
      patch cancel_appointment_path(appointment), params: {
        cancellation: { category: 'cost', details: 'Too expensive' }
      }

      expect(response).to have_http_status(:see_other)
      appointment.reload
      expect(appointment.status).to eq('cancelled')
      expect(appointment.cancellation_reason.reason_category).to eq('cost')
      expect(appointment.cancellation_reason.details).to eq('Too expensive')
    end

    it 'cancels without a reason when none is given' do
      patch cancel_appointment_path(appointment)

      expect(response).to have_http_status(:see_other)
      expect(appointment.reload.status).to eq('cancelled')
      expect(appointment.cancellation_reason).to be_nil
    end
  end

  describe 'PATCH /appointments/:id/confirm' do
    let!(:appointment) { create(:appointment, status: :scheduled) }

    it 'marks the appointment as confirmed' do
      patch confirm_appointment_path(appointment)

      expect(response).to have_http_status(:see_other)
      expect(appointment.reload.status).to eq('confirmed')
    end
  end
end
