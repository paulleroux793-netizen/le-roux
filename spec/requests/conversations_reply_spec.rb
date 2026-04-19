require 'rails_helper'

RSpec.describe 'Conversations reply', type: :request do
  let(:patient) { create(:patient, phone: '+27831234567') }
  let(:conversation) do
    create(:conversation, patient: patient, channel: 'whatsapp', status: 'active',
           messages: [ { role: 'user', content: 'Hi', timestamp: 1.day.ago.iso8601 } ])
  end

  before do
    # Stub the Twilio-backed sender so specs never touch the network.
    @fake = instance_double(WhatsappTemplateService)
    allow(WhatsappTemplateService).to receive(:new).and_return(@fake)
    allow(@fake).to receive(:send_text)
  end

  describe 'POST /conversations/:id/reply' do
    it 'delegates to WhatsappTemplateService#send_text and appends the assistant message' do
      expect(@fake).to receive(:send_text).with(patient.phone, 'Thanks for reaching out!')

      post "/conversations/#{conversation.id}/reply", params: { body: 'Thanks for reaching out!' }

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:notice]).to include('Reply sent')

      conversation.reload
      last = conversation.messages.last
      expect(last['role']).to eq('assistant')
      expect(last['content']).to eq('Thanks for reaching out!')
    end

    it 'reopens a closed conversation when a reply is sent' do
      conversation.update!(status: 'closed')

      post "/conversations/#{conversation.id}/reply", params: { body: 'Checking in' }

      expect(conversation.reload.status).to eq('active')
    end

    it 'rejects empty bodies without calling Twilio' do
      expect(@fake).not_to receive(:send_text)

      post "/conversations/#{conversation.id}/reply", params: { body: '   ' }

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(flash[:alert]).to include('cannot be empty')
    end

    it 'rejects replies on non-whatsapp conversations' do
      voice_conv = create(:conversation, patient: patient, channel: 'voice', status: 'active')
      expect(@fake).not_to receive(:send_text)

      post "/conversations/#{voice_conv.id}/reply", params: { body: 'hi' }
      follow_redirect!
      expect(flash[:alert]).to include('only supported on WhatsApp')
    end

    it 'flashes an alert when Twilio raises' do
      allow(@fake).to receive(:send_text)
        .and_raise(WhatsappTemplateService::Error, 'outside 24h window')

      post "/conversations/#{conversation.id}/reply", params: { body: 'hello' }

      follow_redirect!
      expect(flash[:alert]).to include('Send failed')
      expect(flash[:alert]).to include('outside 24h window')
      # Transcript must NOT have the failed message appended.
      expect(conversation.reload.messages.last['content']).to eq('Hi')
    end
  end
end
