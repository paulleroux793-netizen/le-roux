require 'rails_helper'

RSpec.describe 'Appointments', type: :request do
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
      appointment.reload
      expect(appointment.start_time).to be_within(1.second).of(new_start)
      expect(appointment.end_time).to be_within(1.second).of(new_end)
    end

    it 'rejects invalid times' do
      patch appointment_path(appointment), params: {
        appointment: { start_time: '', end_time: '' }
      }

      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include('Invalid')
    end

    it 'rejects end_time <= start_time' do
      patch appointment_path(appointment), params: {
        appointment: {
          start_time: new_start.iso8601,
          end_time: new_start.iso8601
        }
      }

      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to be_present
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
end
