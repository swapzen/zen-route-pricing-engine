# frozen_string_literal: true

module RoutePricing
  module Services
    class PricingSnapshotManager
      # Capture a snapshot of all active pricings for a city
      def capture(city_code, name, description = '', created_by: nil)
        zone_ids = Zone.where('LOWER(city) = LOWER(?)', city_code).where(status: true).pluck(:id)

        snapshot_data = {
          captured_at: Time.current.iso8601,
          zone_vehicle_pricings: serialize_zone_pricings(zone_ids),
          zone_vehicle_time_pricings: serialize_time_pricings(zone_ids),
          zone_pair_vehicle_pricings: serialize_corridor_pricings(city_code),
          pricing_configs: serialize_city_configs(city_code)
        }

        PricingSnapshot.create!(
          city_code: city_code,
          name: name,
          description: description,
          snapshot_data: snapshot_data,
          created_by: created_by
        )
      end

      # Restore pricings from a snapshot
      def restore(snapshot_id)
        snapshot = PricingSnapshot.find(snapshot_id)
        data = snapshot.snapshot_data

        restored = { zone_pricings: 0, time_pricings: 0, corridor_pricings: 0, configs: 0 }

        ActiveRecord::Base.transaction do
          # Restore zone vehicle pricings
          (data['zone_vehicle_pricings'] || []).each do |attrs|
            record = ZoneVehiclePricing.find_by(id: attrs['id'])
            next unless record

            record.update!(
              base_fare_paise: attrs['base_fare_paise'],
              per_km_rate_paise: attrs['per_km_rate_paise'],
              min_fare_paise: attrs['min_fare_paise'],
              per_min_rate_paise: attrs['per_min_rate_paise']
            )
            restored[:zone_pricings] += 1
          end

          # Restore time band pricings
          (data['zone_vehicle_time_pricings'] || []).each do |attrs|
            record = ZoneVehicleTimePricing.find_by(id: attrs['id'])
            next unless record

            record.update!(
              base_fare_paise: attrs['base_fare_paise'],
              per_km_rate_paise: attrs['per_km_rate_paise'],
              min_fare_paise: attrs['min_fare_paise'],
              per_min_rate_paise: attrs['per_min_rate_paise']
            )
            restored[:time_pricings] += 1
          end

          # Restore corridor pricings
          (data['zone_pair_vehicle_pricings'] || []).each do |attrs|
            record = ZonePairVehiclePricing.find_by(id: attrs['id'])
            next unless record

            record.update!(
              base_fare_paise: attrs['base_fare_paise'],
              per_km_rate_paise: attrs['per_km_rate_paise'],
              min_fare_paise: attrs['min_fare_paise'],
              per_min_rate_paise: attrs['per_min_rate_paise']
            )
            restored[:corridor_pricings] += 1
          end

          # Restore city configs
          (data['pricing_configs'] || []).each do |attrs|
            record = PricingConfig.find_by(id: attrs['id'])
            next unless record

            record.update!(
              base_fare_paise: attrs['base_fare_paise'],
              per_km_rate_paise: attrs['per_km_rate_paise'],
              min_fare_paise: attrs['min_fare_paise'],
              per_min_rate_paise: attrs['per_min_rate_paise']
            )
            restored[:configs] += 1
          end
        end

        { success: true, restored: restored, snapshot_name: snapshot.name }
      end

      # Compare current pricing vs snapshot
      def compare(snapshot_id)
        snapshot = PricingSnapshot.find(snapshot_id)
        data = snapshot.snapshot_data

        diffs = { zone_pricings: [], time_pricings: [], corridor_pricings: [], configs: [] }

        (data['zone_vehicle_pricings'] || []).each do |attrs|
          record = ZoneVehiclePricing.find_by(id: attrs['id'])
          next unless record

          diff = compute_diff(record, attrs, %w[base_fare_paise per_km_rate_paise min_fare_paise per_min_rate_paise])
          if diff.any?
            diffs[:zone_pricings] << {
              id: record.id,
              zone_code: record.zone&.zone_code,
              vehicle_type: record.vehicle_type,
              changes: diff
            }
          end
        end

        (data['zone_vehicle_time_pricings'] || []).each do |attrs|
          record = ZoneVehicleTimePricing.find_by(id: attrs['id'])
          next unless record

          diff = compute_diff(record, attrs, %w[base_fare_paise per_km_rate_paise min_fare_paise per_min_rate_paise])
          if diff.any?
            zvp = record.zone_vehicle_pricing
            diffs[:time_pricings] << {
              id: record.id,
              zone_code: zvp&.zone&.zone_code,
              vehicle_type: zvp&.vehicle_type,
              time_band: record.time_band,
              changes: diff
            }
          end
        end

        (data['zone_pair_vehicle_pricings'] || []).each do |attrs|
          record = ZonePairVehiclePricing.find_by(id: attrs['id'])
          next unless record

          diff = compute_diff(record, attrs, %w[base_fare_paise per_km_rate_paise min_fare_paise per_min_rate_paise])
          if diff.any?
            diffs[:corridor_pricings] << {
              id: record.id,
              from_zone: record.from_zone&.zone_code,
              to_zone: record.to_zone&.zone_code,
              vehicle_type: record.vehicle_type,
              time_band: record.time_band,
              changes: diff
            }
          end
        end

        {
          snapshot_name: snapshot.name,
          captured_at: data['captured_at'],
          total_changes: diffs.values.sum(&:size),
          diffs: diffs
        }
      end

      # List snapshots for a city
      def list(city_code)
        PricingSnapshot.for_city(city_code).recent.limit(50)
      end

      private

      def serialize_zone_pricings(zone_ids)
        ZoneVehiclePricing.where(zone_id: zone_ids, active: true).map do |zvp|
          {
            id: zvp.id,
            zone_id: zvp.zone_id,
            vehicle_type: zvp.vehicle_type,
            base_fare_paise: zvp.base_fare_paise,
            per_km_rate_paise: zvp.per_km_rate_paise,
            min_fare_paise: zvp.min_fare_paise,
            per_min_rate_paise: zvp.try(:per_min_rate_paise)
          }
        end
      end

      def serialize_time_pricings(zone_ids)
        zvp_ids = ZoneVehiclePricing.where(zone_id: zone_ids, active: true).pluck(:id)
        ZoneVehicleTimePricing.where(zone_vehicle_pricing_id: zvp_ids, active: true).map do |tp|
          {
            id: tp.id,
            zone_vehicle_pricing_id: tp.zone_vehicle_pricing_id,
            time_band: tp.time_band,
            base_fare_paise: tp.base_fare_paise,
            per_km_rate_paise: tp.per_km_rate_paise,
            min_fare_paise: tp.min_fare_paise,
            per_min_rate_paise: tp.try(:per_min_rate_paise)
          }
        end
      end

      def serialize_corridor_pricings(city_code)
        ZonePairVehiclePricing.where('LOWER(city_code) = LOWER(?)', city_code).where(active: true).map do |zpvp|
          {
            id: zpvp.id,
            from_zone_id: zpvp.from_zone_id,
            to_zone_id: zpvp.to_zone_id,
            vehicle_type: zpvp.vehicle_type,
            time_band: zpvp.time_band,
            base_fare_paise: zpvp.base_fare_paise,
            per_km_rate_paise: zpvp.per_km_rate_paise,
            min_fare_paise: zpvp.min_fare_paise,
            per_min_rate_paise: zpvp.try(:per_min_rate_paise)
          }
        end
      end

      def serialize_city_configs(city_code)
        PricingConfig.where(city_code: city_code, active: true).map do |config|
          {
            id: config.id,
            vehicle_type: config.vehicle_type,
            base_fare_paise: config.base_fare_paise,
            per_km_rate_paise: config.per_km_rate_paise,
            min_fare_paise: config.min_fare_paise,
            per_min_rate_paise: config.try(:per_min_rate_paise)
          }
        end
      end

      def compute_diff(record, snapshot_attrs, fields)
        diff = {}
        fields.each do |field|
          current_val = record.try(field)
          snapshot_val = snapshot_attrs[field]
          if current_val != snapshot_val
            diff[field] = { current: current_val, snapshot: snapshot_val }
          end
        end
        diff
      end
    end
  end
end
