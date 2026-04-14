require 'rails_helper'

RSpec.describe WhatsappImportService do
  describe '.import_file (JSON)' do
    let(:path) { Rails.root.join('tmp', 'test_whatsapp_import.json') }

    after { File.delete(path) if File.exist?(path) }

    it 'creates conversations + patients from a JSON export' do
      payload = [
        {
          phone: '+27831234567',
          name:  'Emily Clark',
          messages: [
            { from: 'patient', text: "Hi, I'd like to book an appointment", timestamp: '2024-01-15T10:23:00Z' },
            { from: 'clinic',  text: 'Tuesday at 10?',                      timestamp: '2024-01-15T10:24:00Z' }
          ]
        },
        {
          phone: '+27849999999',
          name:  'John Doe',
          topic: 'Custom topic override',
          messages: [
            { from: 'patient', text: 'Payment question',  timestamp: '2024-01-16T09:00:00Z' },
            { from: 'clinic',  text: "We'll send an invoice", timestamp: '2024-01-16T09:02:00Z' }
          ]
        }
      ]
      File.write(path, JSON.dump(payload))

      expect {
        result = described_class.import_file(path.to_s)
        expect(result.created).to eq(2)
        expect(result.updated).to eq(0)
        expect(result.errors).to be_empty
      }.to change(Conversation, :count).by(2).and change(Patient, :count).by(2)

      emily = Conversation.joins(:patient).find_by(patients: { phone: '+27831234567' })
      expect(emily.source).to eq('import')
      expect(emily.channel).to eq('whatsapp')
      expect(emily.status).to eq('closed')
      expect(emily.topic).to eq('Appointment booking')       # classifier
      expect(emily.messages.length).to eq(2)
      expect(emily.messages.first['role']).to eq('user')
      expect(emily.messages.last['role']).to eq('assistant')
      expect(emily.external_id).to be_present
      expect(emily.imported_at).to be_present

      john = Conversation.joins(:patient).find_by(patients: { phone: '+27849999999' })
      expect(john.topic).to eq('Custom topic override')       # explicit topic wins
    end

    it 'is idempotent — re-running the same file updates instead of duplicating' do
      payload = [{
        phone: '+27831234567', name: 'Emily Clark',
        messages: [{ from: 'patient', text: 'Hi', timestamp: '2024-01-15T10:23:00Z' }]
      }]
      File.write(path, JSON.dump(payload))

      described_class.import_file(path.to_s)
      expect {
        result = described_class.import_file(path.to_s)
        expect(result.updated).to eq(1)
        expect(result.created).to eq(0)
      }.not_to change(Conversation, :count)
    end

    it 'reuses an existing patient matched by phone' do
      existing = create(:patient, phone: '+27831234567', first_name: 'Existing', last_name: 'Person')
      File.write(path, JSON.dump([{
        phone: '+27831234567', name: 'Emily Clark',
        messages: [{ from: 'patient', text: 'Hello', timestamp: '2024-01-15T10:23:00Z' }]
      }]))

      expect { described_class.import_file(path.to_s) }.not_to change(Patient, :count)
      expect(Conversation.last.patient_id).to eq(existing.id)
    end

    it 'records errors for malformed threads without aborting the batch' do
      File.write(path, JSON.dump([
        { phone: nil, messages: [] },  # bad
        { phone: '+27831112222', name: 'OK', messages: [{ from: 'patient', text: 'hi', timestamp: '2024-01-15T10:00:00Z' }] }
      ]))

      result = described_class.import_file(path.to_s)
      expect(result.created).to eq(1)
      expect(result.skipped).to eq(1)
      expect(result.errors.length).to eq(1)
    end

    it 'raises ImportError on invalid JSON' do
      File.write(path, 'not-json')
      expect { described_class.import_file(path.to_s) }
        .to raise_error(WhatsappImportService::ImportError, /invalid JSON/)
    end
  end

  describe '.import_file (TXT)' do
    let(:path) { Rails.root.join('tmp', 'test_whatsapp_import.txt') }
    after { File.delete(path) if File.exist?(path) }

    it 'parses iOS bracketed format' do
      File.write(path, <<~TXT)
        [2024-01-15, 10:23:45] Emily Clark: Hi, I'd like to book an appointment
        [2024-01-15, 10:24:02] Dr Le Roux: Sure — Tuesday at 10?
        [2024-01-15, 10:24:30] Emily Clark: Perfect, thanks!
      TXT

      result = described_class.import_file(
        path.to_s, owner_name: 'Dr Le Roux', patient_phone: '+27831234567'
      )

      expect(result.created).to eq(1)
      convo = Conversation.last
      expect(convo.messages.length).to eq(3)
      expect(convo.messages[0]['role']).to eq('user')
      expect(convo.messages[1]['role']).to eq('assistant')
      expect(convo.topic).to eq('Appointment booking')
      expect(convo.patient.first_name).to eq('Emily')
      expect(convo.patient.last_name).to eq('Clark')
    end

    it 'parses Android dashed format' do
      File.write(path, <<~TXT)
        15/01/2024, 10:23 - Emily Clark: Hi, I need to reschedule
        15/01/2024, 10:24 - Dr Le Roux: No problem, when suits you?
      TXT

      described_class.import_file(
        path.to_s, owner_name: 'Dr Le Roux', patient_phone: '+27831234567'
      )

      convo = Conversation.last
      expect(convo.messages.length).to eq(2)
      expect(convo.topic).to eq('Appointment rescheduling')
    end

    it 'appends continuation lines to the previous message' do
      File.write(path, <<~TXT)
        [2024-01-15, 10:23:45] Emily Clark: Line one
        line two
        line three
        [2024-01-15, 10:24:02] Dr Le Roux: Got it
      TXT

      described_class.import_file(
        path.to_s, owner_name: 'Dr Le Roux', patient_phone: '+27831234567'
      )

      convo = Conversation.last
      expect(convo.messages.length).to eq(2)
      expect(convo.messages.first['content']).to eq("Line one\nline two\nline three")
    end

    it 'raises when patient_phone is missing for a .txt' do
      File.write(path, "[2024-01-15, 10:23:45] Emily: hi\n")
      expect {
        described_class.import_file(path.to_s, owner_name: 'Dr', patient_phone: nil)
      }.to raise_error(WhatsappImportService::ImportError, /patient_phone/)
    end
  end
end
