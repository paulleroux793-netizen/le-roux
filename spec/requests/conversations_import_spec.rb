require 'rails_helper'
require 'inertia_rails/rspec'

RSpec.describe 'Conversations import', type: :request do
  let(:json_file) do
    path = Rails.root.join('tmp', 'request_import.json')
    File.write(path, JSON.dump([ {
      phone: '+27831234567',
      name:  'Emily Clark',
      messages: [
        { from: 'patient', text: 'Hi, need appointment', timestamp: '2024-01-15T10:23:00Z' }
      ]
    } ]))
    Rack::Test::UploadedFile.new(path, 'application/json')
  end

  after do
    path = Rails.root.join('tmp', 'request_import.json')
    File.delete(path) if File.exist?(path)
  end

  describe 'POST /conversations/import' do
    it 'imports a JSON export and redirects with a notice' do
      expect {
        post '/conversations/import', params: { file: json_file }
      }.to change(Conversation, :count).by(1)

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:notice]).to include('Import complete')
      expect(flash[:notice]).to include('1 created')
    end

    it 'redirects with an alert when no file is supplied' do
      post '/conversations/import', params: {}
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:alert]).to include('choose a file')
    end

    it 'exposes topic + source + whatsapp_url in index props' do
      post '/conversations/import', params: { file: json_file }

      get '/conversations'
      conv = inertia.props[:conversations].first
      expect(conv[:source]).to eq('import')
      expect(conv[:topic]).to be_present
      expect(conv[:whatsapp_url]).to start_with('https://wa.me/')
    end
  end
end
