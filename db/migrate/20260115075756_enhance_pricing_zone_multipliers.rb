# frozen_string_literal: true

# Migration to enhance PricingZoneMultipliers with vehicle-category-specific multipliers
# and zone type classification for intelligent zone-based pricing
class EnhancePricingZoneMultipliers < ActiveRecord::Migration[7.0]
  def change
    # Add vehicle-category specific multipliers (replacing single multiplier)
    add_column :pricing_zone_multipliers, :small_vehicle_mult, :decimal, 
               precision: 4, scale: 2, default: 1.0, 
               comment: 'Multiplier for 2W/Scooter/Mini3W'
    
    add_column :pricing_zone_multipliers, :mid_truck_mult, :decimal, 
               precision: 4, scale: 2, default: 1.0,
               comment: 'Multiplier for 3W/TataAce/Pickup8ft'
    
    add_column :pricing_zone_multipliers, :heavy_truck_mult, :decimal, 
               precision: 4, scale: 2, default: 1.0,
               comment: 'Multiplier for Eeco/Tata407/Canter'
    
    # Add zone type for business logic (tech_corridor, residential, etc.)
    add_column :pricing_zone_multipliers, :zone_type, :string,
               comment: 'Business zone classification'
    
    # Add metadata for future features (demand patterns, time-specific rules, etc.)
    add_column :pricing_zone_multipliers, :metadata, :jsonb, 
               default: {},
               comment: 'Extensible metadata for zone-specific features'
    
    # Migrate existing multiplier to new vehicle-category columns
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE pricing_zone_multipliers
          SET small_vehicle_mult = multiplier,
              mid_truck_mult = multiplier,
              heavy_truck_mult = multiplier
          WHERE multiplier IS NOT NULL
        SQL
      end
    end
    
    # Add index on zone_type for filtering
    add_index :pricing_zone_multipliers, :zone_type
    
    # Keep old multiplier column for backward compatibility (can remove in future)
    # remove_column :pricing_zone_multipliers, :multiplier
  end
end
