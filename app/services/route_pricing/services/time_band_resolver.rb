# frozen_string_literal: true

module RoutePricing
  module Services
    class TimeBandResolver
      BANDS = {
        early_morning:  { hours: 5...8,   weekday_only: true,  fallback: 'morning',   label: 'Early Morning' },
        morning_rush:   { hours: 8...11,  weekday_only: true,  fallback: 'morning',   label: 'Morning Rush' },
        midday:         { hours: 11...14, weekday_only: true,  fallback: 'afternoon', label: 'Midday' },
        afternoon:      { hours: 14...17, weekday_only: true,  fallback: 'afternoon', label: 'Afternoon' },
        evening_rush:   { hours: 17...21, weekday_only: true,  fallback: 'evening',   label: 'Evening Rush' },
        night:          { hours: nil,     weekday_only: false, fallback: 'evening',   label: 'Night' },
        weekend_day:    { hours: 8...20,  weekday_only: false, fallback: 'afternoon', label: 'Weekend Day' },
        weekend_night:  { hours: nil,     weekday_only: false, fallback: 'evening',   label: 'Weekend Night' },
      }.freeze

      def self.resolve(local_time)
        hour = local_time.hour
        weekend = local_time.saturday? || local_time.sunday?

        if weekend
          return 'weekend_day' if (8...20).include?(hour)
          return 'weekend_night'
        end

        case hour
        when 5...8   then 'early_morning'
        when 8...11  then 'morning_rush'
        when 11...14 then 'midday'
        when 14...17 then 'afternoon'
        when 17...21 then 'evening_rush'
        else 'night'
        end
      end

      def self.fallback_band(band)
        BANDS[band.to_sym]&.dig(:fallback) || band
      end

      def self.all_bands
        BANDS.keys.map(&:to_s)
      end

      def self.label(band)
        BANDS[band.to_sym]&.dig(:label) || band.to_s.titleize
      end
    end
  end
end
