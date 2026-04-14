require 'rails_helper'

RSpec.describe 'Notifications', type: :request do
  describe 'GET /notifications' do
    it 'returns the latest notifications + unread count as JSON' do
      create(:notification, :read,   title: 'Old')
      create(:notification, :unread, title: 'New one')
      create(:notification, :unread, title: 'Newer')

      get '/notifications'

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['notifications'].length).to eq(3)
      expect(json['notifications'].first['title']).to eq('Newer')
      expect(json['unread_count']).to eq(2)
    end

    it 'caps results at LIST_LIMIT' do
      create_list(:notification, NotificationsController::LIST_LIMIT + 5)
      get '/notifications'
      expect(response.parsed_body['notifications'].length).to eq(NotificationsController::LIST_LIMIT)
    end
  end

  describe 'PATCH /notifications/:id/mark_read' do
    it 'marks a single notification as read' do
      n = create(:notification, :unread)
      Rails.cache.write('notifications/unread_count', 4)

      patch "/notifications/#{n.id}/mark_read"

      expect(response).to have_http_status(:ok)
      expect(n.reload.read?).to be(true)
      expect(response.parsed_body['unread_count']).to eq(0)
      expect(Rails.cache.exist?('notifications/unread_count')).to be(false)
    end

    it 'is idempotent on already-read notifications' do
      n = create(:notification, :read)
      expect { patch "/notifications/#{n.id}/mark_read" }.not_to raise_error
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /notifications/mark_all_read' do
    it 'clears the unread queue' do
      create_list(:notification, 3, :unread)
      create(:notification, :read)
      Rails.cache.write('notifications/unread_count', 3)

      post '/notifications/mark_all_read'

      expect(response).to have_http_status(:ok)
      expect(Notification.unread.count).to eq(0)
      expect(response.parsed_body['unread_count']).to eq(0)
      expect(Rails.cache.exist?('notifications/unread_count')).to be(false)
    end
  end
end

RSpec.describe NotificationService do
  describe '.appointment_created' do
    it 'emits an appointment_created notification tied to the patient + appointment' do
      appt = create(:appointment)

      expect {
        described_class.appointment_created(appt)
      }.to change(Notification, :count).by(1)

      n = Notification.last
      expect(n.category).to eq('appointment_created')
      expect(n.level).to eq('info')
      expect(n.patient_id).to eq(appt.patient_id)
      expect(n.appointment_id).to eq(appt.id)
      expect(n.url).to eq("/appointments/#{appt.id}")
    end
  end

  describe '.appointment_cancelled' do
    it 'emits a warning-level notification with the reason in the body' do
      appt = create(:appointment)
      described_class.appointment_cancelled(appt, reason: 'cost')

      n = Notification.last
      expect(n.category).to eq('appointment_cancelled')
      expect(n.level).to eq('warning')
      expect(n.body).to include('cost')
    end
  end

  describe '.appointment_confirmed' do
    it 'emits a success-level notification' do
      appt = create(:appointment)
      described_class.appointment_confirmed(appt)
      expect(Notification.last.level).to eq('success')
    end
  end

  describe '.patient_created' do
    it 'emits a patient_created notification' do
      patient = create(:patient)
      Rails.cache.write('notifications/unread_count', 99)
      described_class.patient_created(patient)

      n = Notification.last
      expect(n.category).to eq('patient_created')
      expect(n.patient_id).to eq(patient.id)
      expect(Rails.cache.exist?('notifications/unread_count')).to be(false)
    end
  end

  describe 'resilience' do
    it 'swallows DB errors and logs instead of raising' do
      allow(Notification).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new('boom'))
      expect(Rails.logger).to receive(:error).with(/NotificationService/)

      expect {
        described_class.patient_created(create(:patient))
      }.not_to raise_error
    end
  end
end

RSpec.describe 'Controller integration with notifications', type: :request do
  it 'emits a notification when an appointment is confirmed' do
    appt = create(:appointment, status: :scheduled)

    expect {
      patch "/appointments/#{appt.id}/confirm"
    }.to change { Notification.where(category: 'appointment_confirmed').count }.by(1)
  end

  it 'emits a notification when a patient is created' do
    expect {
      post '/patients', params: {
        patient: {
          first_name: 'New', last_name: 'Patient',
          phone: '+27820000001'
        }
      }
    }.to change { Notification.where(category: 'patient_created').count }.by(1)
  end

  it 'emits a cancelled notification when an appointment is cancelled' do
    appt = create(:appointment)
    expect {
      patch "/appointments/#{appt.id}/cancel", params: {
        cancellation: { category: 'cost' }
      }
    }.to change { Notification.where(category: 'appointment_cancelled').count }.by(1)
  end
end
