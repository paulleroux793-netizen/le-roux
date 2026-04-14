require 'rails_helper'

RSpec.describe 'Performance', type: :request do
  before do
    Rails.cache.clear
  end

  describe 'page query counts' do
    before do
      create_list(:notification, 2, :unread)

      patients = create_list(:patient, 4)

      patients.each_with_index do |patient, index|
        create(:appointment,
          patient: patient,
          start_time: Time.zone.now.beginning_of_day + (9 + index).hours,
          end_time: Time.zone.now.beginning_of_day + (9 + index).hours + 30.minutes,
          status: index.even? ? :scheduled : :confirmed
        )
      end

      flagged_appointment = create(:appointment,
        patient: patients.first,
        start_time: Time.zone.now.beginning_of_day + 15.hours,
        end_time: Time.zone.now.beginning_of_day + 15.hours + 30.minutes,
        status: :scheduled
      )
      create(:confirmation_log, appointment: flagged_appointment, flagged: true)

      create(:conversation, patient: patients.first, channel: 'whatsapp', updated_at: 1.day.ago)
      create(:conversation, patient: patients.second, channel: 'voice', updated_at: 2.days.ago)

      create(:doctor_schedule, day_of_week: 1)
    end

    it 'keeps dashboard queries bounded' do
      queries = capture_queries { get '/' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 5
    end

    it 'keeps appointments index queries bounded' do
      queries = capture_queries { get '/appointments' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 7
    end

    it 'keeps patients index queries bounded' do
      queries = capture_queries { get '/patients' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 7
    end

    it 'keeps conversations index queries bounded' do
      queries = capture_queries { get '/conversations' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 3
    end

    it 'keeps reminders index queries bounded' do
      queries = capture_queries { get '/reminders' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 4
    end

    it 'keeps analytics queries bounded' do
      queries = capture_queries { get '/analytics' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 5
    end

    it 'keeps settings queries bounded' do
      queries = capture_queries { get '/settings' }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 2
    end
  end

  describe 'search endpoint queries' do
    it 'avoids loading one patient query per search result' do
      patient = create(:patient, first_name: 'Alice', last_name: 'Ndlovu')
      create(:appointment, patient: patient, reason: 'Cleaning')
      create(:conversation, patient: patient, channel: 'whatsapp')

      queries = capture_queries { get '/search', params: { q: 'Alice' } }

      expect(response).to have_http_status(:ok)
      expect(queries.size).to be <= 3
      expect(queries.grep(/FROM "patients" WHERE "patients"\."id"/)).to be_empty
    end
  end
end
