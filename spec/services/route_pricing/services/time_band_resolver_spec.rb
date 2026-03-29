# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::TimeBandResolver do
  describe '.resolve' do
    let(:ist) { ActiveSupport::TimeZone['Asia/Kolkata'] }

    # Weekday bands
    it 'returns early_morning for weekday 6 AM IST' do
      time = ist.local(2026, 3, 30, 6, 0) # Monday
      expect(described_class.resolve(time)).to eq('early_morning')
    end

    it 'returns morning_rush for weekday 9 AM IST' do
      time = ist.local(2026, 3, 30, 9, 0)
      expect(described_class.resolve(time)).to eq('morning_rush')
    end

    it 'returns midday for weekday 12 PM IST' do
      time = ist.local(2026, 3, 30, 12, 0)
      expect(described_class.resolve(time)).to eq('midday')
    end

    it 'returns afternoon for weekday 3 PM IST' do
      time = ist.local(2026, 3, 30, 15, 0)
      expect(described_class.resolve(time)).to eq('afternoon')
    end

    it 'returns evening_rush for weekday 7 PM IST' do
      time = ist.local(2026, 3, 30, 19, 0)
      expect(described_class.resolve(time)).to eq('evening_rush')
    end

    it 'returns night for weekday 11 PM IST' do
      time = ist.local(2026, 3, 30, 23, 0)
      expect(described_class.resolve(time)).to eq('night')
    end

    it 'returns night for weekday 3 AM IST' do
      time = ist.local(2026, 3, 30, 3, 0)
      expect(described_class.resolve(time)).to eq('night')
    end

    # Weekend bands
    it 'returns weekend_day for Saturday 10 AM IST' do
      time = ist.local(2026, 3, 28, 10, 0) # Saturday
      expect(described_class.resolve(time)).to eq('weekend_day')
    end

    it 'returns weekend_night for Sunday 21:00 IST' do
      time = ist.local(2026, 3, 29, 21, 0) # Sunday
      expect(described_class.resolve(time)).to eq('weekend_night')
    end

    it 'returns weekend_night for Saturday 3 AM IST' do
      time = ist.local(2026, 3, 28, 3, 0)
      expect(described_class.resolve(time)).to eq('weekend_night')
    end

    # Timezone conversion
    it 'converts UTC time to IST before resolving' do
      # 3:30 AM UTC = 9:00 AM IST (morning_rush on weekday)
      utc_time = Time.utc(2026, 3, 30, 3, 30) # Monday UTC
      expect(described_class.resolve(utc_time)).to eq('morning_rush')
    end
  end

  describe '.all_bands' do
    it 'returns all 8 band names' do
      expect(described_class.all_bands.size).to eq(8)
      expect(described_class.all_bands).to include('morning_rush', 'evening_rush', 'weekend_day')
    end
  end

  describe '.label' do
    it 'returns human-readable label' do
      expect(described_class.label('morning_rush')).to eq('Morning Rush')
    end
  end
end
