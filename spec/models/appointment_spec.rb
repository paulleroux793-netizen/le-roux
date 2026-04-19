require 'rails_helper'

RSpec.describe Appointment, type: :model do
  describe 'validations' do
    it 'requires end_time to be after start_time' do
      appointment = build(:appointment,
        start_time: Time.zone.local(2026, 5, 14, 9, 0),
        end_time: Time.zone.local(2026, 5, 14, 9, 0)
      )

      expect(appointment).not_to be_valid
      expect(appointment.errors[:end_time]).to include('must be after start time')
    end
  end

  describe '.upcoming' do
    it 'returns future non-cancelled appointments in chronological order' do
      later = create(:appointment, start_time: 2.days.from_now, end_time: 2.days.from_now + 30.minutes)
      sooner = create(:appointment, start_time: 1.day.from_now, end_time: 1.day.from_now + 30.minutes)
      create(:appointment, :cancelled, start_time: 3.days.from_now, end_time: 3.days.from_now + 30.minutes)
      create(:appointment, start_time: 1.day.ago, end_time: 1.day.ago + 30.minutes)

      expect(described_class.upcoming).to eq([ sooner, later ])
    end
  end
end
