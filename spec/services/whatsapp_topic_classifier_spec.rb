require 'rails_helper'

RSpec.describe WhatsappTopicClassifier do
  describe '.classify' do
    it 'returns General enquiry for blank input' do
      expect(described_class.classify(nil)).to eq('General enquiry')
      expect(described_class.classify('')).to eq('General enquiry')
    end

    it 'classifies booking intents' do
      expect(described_class.classify("Hi, I'd like to book an appointment"))
        .to eq('Appointment booking')
    end

    it 'classifies rescheduling before booking' do
      # Order matters — a "reschedule my appointment" message must
      # land on the reschedule rule, not the generic booking rule.
      expect(described_class.classify('Can I reschedule my appointment please?'))
        .to eq('Appointment rescheduling')
    end

    it 'classifies cancellations' do
      expect(described_class.classify('I need to cancel tomorrow'))
        .to eq('Appointment cancellation')
    end

    it 'classifies confirmations' do
      expect(described_class.classify('Confirming for 10am'))
        .to eq('Appointment confirmation')
    end

    it 'classifies dental emergencies' do
      expect(described_class.classify('Emergency — severe pain after surgery'))
        .to eq('Dental emergency')
    end

    it 'classifies billing questions' do
      expect(described_class.classify('Query about my invoice for last visit'))
        .to eq('Billing / payment')
    end

    it 'falls back to General enquiry for unmatched text' do
      expect(described_class.classify('Just saying hello!')).to eq('General enquiry')
    end
  end
end
