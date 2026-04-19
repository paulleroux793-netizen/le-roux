require 'rails_helper'

RSpec.describe 'Search', type: :request do
  describe 'GET /search' do
    let!(:alice)  { create(:patient, first_name: 'Alice',  last_name: 'Ndlovu', phone: '+27821110001', email: 'alice@example.com') }
    let!(:bob)    { create(:patient, first_name: 'Bob',    last_name: 'Smith',  phone: '+27821110002', email: 'bob@example.com') }
    let!(:carol)  { create(:patient, first_name: 'Carol',  last_name: 'Jones',  phone: '+27821110003', email: 'carol@example.com') }

    let!(:alice_appt) { create(:appointment, patient: alice, reason: 'Root canal') }
    let!(:bob_appt)   { create(:appointment, patient: bob,   reason: 'Cleaning') }

    let!(:alice_convo) { create(:conversation, patient: alice, channel: 'whatsapp') }

    it 'returns an empty payload for queries under the minimum length' do
      get '/search', params: { q: 'a' }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['patients']).to eq([])
      expect(json['appointments']).to eq([])
      expect(json['conversations']).to eq([])
    end

    it 'finds patients by first name' do
      get '/search', params: { q: 'Alice' }

      json = response.parsed_body
      expect(json['patients'].map { |p| p['full_name'] }).to include('Alice Ndlovu')
      expect(json['patients'].map { |p| p['full_name'] }).not_to include('Bob Smith')
    end

    it 'finds patients by last name' do
      get '/search', params: { q: 'Ndlovu' }
      expect(response.parsed_body['patients'].first['full_name']).to eq('Alice Ndlovu')
    end

    it 'finds patients by full name substring' do
      get '/search', params: { q: 'Alice Nd' }
      expect(response.parsed_body['patients'].first['full_name']).to eq('Alice Ndlovu')
    end

    it 'finds patients by phone' do
      get '/search', params: { q: '1110002' }
      expect(response.parsed_body['patients'].first['full_name']).to eq('Bob Smith')
    end

    it 'finds patients by email' do
      get '/search', params: { q: 'carol@' }
      expect(response.parsed_body['patients'].first['full_name']).to eq('Carol Jones')
    end

    it 'finds appointments by patient name' do
      get '/search', params: { q: 'Alice' }
      expect(response.parsed_body['appointments'].map { |a| a['id'] }).to include(alice_appt.id)
    end

    it 'finds appointments by reason' do
      get '/search', params: { q: 'Root canal' }
      expect(response.parsed_body['appointments'].map { |a| a['id'] }).to eq([ alice_appt.id ])
    end

    it 'finds conversations by patient name' do
      get '/search', params: { q: 'Alice' }
      expect(response.parsed_body['conversations'].map { |c| c['id'] }).to include(alice_convo.id)
    end

    it 'escapes LIKE wildcards so "%" is treated literally' do
      get '/search', params: { q: '%' }
      # "%" is 1 char, below MIN_QUERY_LENGTH → empty payload
      expect(response.parsed_body['patients']).to eq([])

      # "%%" passes length check but should match nothing literal.
      get '/search', params: { q: '%%' }
      expect(response.parsed_body['patients']).to eq([])
    end

    it 'caps results per group at RESULT_LIMIT' do
      create_list(:patient, 10, first_name: 'Zoe')
      get '/search', params: { q: 'Zoe' }
      expect(response.parsed_body['patients'].length).to eq(SearchController::RESULT_LIMIT)
    end

    it 'returns JSON with a query echo' do
      get '/search', params: { q: 'Alice' }
      expect(response.media_type).to eq('application/json')
      expect(response.parsed_body['query']).to eq('Alice')
    end
  end
end
