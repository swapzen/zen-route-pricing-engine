# frozen_string_literal: true

module RoutePricing
  module Services
    class TimeBandResolver
      # 8 granular time bands — India-only, Asia/Kolkata timezone
      BANDS = {
        early_morning:  { hours: 5...8,   weekday_only: true,  label: 'Early Morning' },
        morning_rush:   { hours: 8...11,  weekday_only: true,  label: 'Morning Rush' },
        midday:         { hours: 11...14, weekday_only: true,  label: 'Midday' },
        afternoon:      { hours: 14...17, weekday_only: true,  label: 'Afternoon' },
        evening_rush:   { hours: 17...21, weekday_only: true,  label: 'Evening Rush' },
        night:          { hours: nil,     weekday_only: false, label: 'Night' },
        weekend_day:    { hours: 8...20,  weekday_only: false, label: 'Weekend Day' },
        weekend_night:  { hours: nil,     weekday_only: false, label: 'Weekend Night' },
      }.freeze

      TIMEZONE = 'Asia/Kolkata'

      # Resolve current time to one of 8 bands
      def self.resolve(local_time)
        local_time = local_time.in_time_zone(TIMEZONE) if local_time.respond_to?(:in_time_zone)
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

      # Resolve from current time (convenience)
      def self.current_band
        resolve(Time.current.in_time_zone(TIMEZONE))
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
