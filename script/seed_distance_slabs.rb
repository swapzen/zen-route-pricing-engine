# frozen_string_literal: true

# Seed PricingDistanceSlab from vehicle_defaults.yml
require "yaml"

defaults = YAML.load_file(Rails.root.join("config/zones/hyderabad/vehicle_defaults.yml"))
vehicles = defaults["vehicles"] || {}
created = 0

vehicles.each do |vehicle_type, config|
  slabs = config["slabs"]
  next unless slabs

  pc = PricingConfig.find_by(city_code: "hyd", vehicle_type: vehicle_type, active: true)
  unless pc
    puts "  SKIP #{vehicle_type}: no PricingConfig found"
    next
  end

  slabs.each do |slab|
    min_m, max_m, rate = slab
    max_m = 999_999 if max_m.nil?

    ds = PricingDistanceSlab.find_or_initialize_by(
      pricing_config_id: pc.id,
      min_distance_m: min_m
    )
    ds.max_distance_m = max_m
    ds.per_km_rate_paise = rate
    if ds.new_record? || ds.changed?
      ds.save!
      created += 1
    end
  end
end

puts "Created #{created} PricingDistanceSlab records"
puts "Total: #{PricingDistanceSlab.count}"
PricingDistanceSlab.joins(:pricing_config).order("pricing_configs.vehicle_type", :min_distance_m).each do |ds|
  puts "  #{ds.pricing_config.vehicle_type}: #{ds.min_distance_m}-#{ds.max_distance_m}m @ #{ds.per_km_rate_paise} paise/km"
end
