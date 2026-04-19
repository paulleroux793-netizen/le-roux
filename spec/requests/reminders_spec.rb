require 'rails_helper'
require 'inertia_rails/rspec'

RSpec.describe 'Reminders', type: :request do
  describe 'GET /reminders' do
    def build_appt(status:, start_time:)
      create(:appointment, status: status, start_time: start_time, end_time: start_time + 30.minutes)
    end

    it 'renders the inertia reminders page with upcoming unconfirmed appointments' do
      build_appt(status: :scheduled, start_time: 2.hours.from_now)
      build_appt(status: :confirmed, start_time: 3.hours.from_now)  # included (now shows all statuses)
      build_appt(status: :scheduled, start_time: 2.days.from_now)
      build_appt(status: :scheduled, start_time: 10.days.from_now)  # outside window

      get '/reminders'

      expect(response).to have_http_status(:ok)
    end

    it 'scopes to the WINDOW_DAYS window' do
      in_window  = build_appt(status: :scheduled, start_time: 6.days.from_now)
      out_window = build_appt(status: :scheduled, start_time: 15.days.from_now)

      get '/reminders'
      ids = inertia.props[:reminders].map { |r| r[:id] }
      expect(ids).to include(in_window.id)
      expect(ids).not_to include(out_window.id)
    end

    it 'includes confirmed appointments with Confirmed status' do
      confirmed = build_appt(status: :confirmed, start_time: 2.hours.from_now)

      get '/reminders'
      reminders = inertia.props[:reminders]
      match = reminders.find { |r| r[:id] == confirmed.id }
      expect(match).to be_present
      expect(match[:reminder_status]).to eq("Confirmed")
    end
  end

  describe 'POST /reminders/:appointment_id/send' do
    let!(:appointment) { create(:appointment, status: :scheduled, start_time: 2.hours.from_now) }

    it 'delegates WhatsApp sends to ConfirmationService.send_reminder' do
      expect(ConfirmationService).to receive(:send_reminder).with(
        an_instance_of(Appointment), method: 'whatsapp'
      )

      post "/reminders/#{appointment.id}/send", params: { method: 'whatsapp' }

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:notice]).to include('Whatsapp reminder sent')
    end

    it 'delegates voice sends to ConfirmationService.send_reminder' do
      expect(ConfirmationService).to receive(:send_reminder).with(
        an_instance_of(Appointment), method: 'voice'
      )

      post "/reminders/#{appointment.id}/send", params: { method: 'voice' }

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:notice]).to include('Voice reminder sent')
    end

    it 'defaults to whatsapp when no method is passed' do
      expect(ConfirmationService).to receive(:send_reminder).with(
        an_instance_of(Appointment), method: 'whatsapp'
      )

      post "/reminders/#{appointment.id}/send"
      expect(response).to have_http_status(:see_other)
    end

    it 'flashes an alert when dispatch fails' do
      allow(ConfirmationService).to receive(:send_reminder)
        .and_raise(ConfirmationService::SendError, 'Twilio down')

      post "/reminders/#{appointment.id}/send", params: { method: 'whatsapp' }

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:alert]).to include('Reminder failed')
      expect(flash[:alert]).to include('Twilio down')
    end
  end
end

RSpec.describe ConfirmationService, '.send_reminder' do
  let(:appointment) { create(:appointment, status: :scheduled, start_time: 2.hours.from_now) }

  it 'creates a ConfirmationLog for the whatsapp path' do
    fake_service = instance_double(WhatsappTemplateService, send_reminder_24h: true)
    allow(WhatsappTemplateService).to receive(:new).and_return(fake_service)

    expect {
      ConfirmationService.send_reminder(appointment, method: 'whatsapp')
    }.to change(ConfirmationLog, :count).by(1)

    log = ConfirmationLog.last
    expect(log.method).to eq('whatsapp')
    expect(log.attempts).to eq(1)
  end

  it 'raises SendError when WhatsApp dispatch fails' do
    allow(WhatsappTemplateService).to receive(:new).and_raise(StandardError, 'boom')

    expect {
      ConfirmationService.send_reminder(appointment, method: 'whatsapp')
    }.to raise_error(ConfirmationService::SendError, /boom/)
  end

  it 'rejects unknown methods' do
    expect {
      ConfirmationService.send_reminder(appointment, method: 'email')
    }.to raise_error(ConfirmationService::SendError)
  end
end
