class CreatePricingTables < ActiveRecord::Migration[8.0]
  def change
    # Pricing configurations (master data)
    create_table :pricing_configs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :city_code, null: false
      t.string :vehicle_type, null: false
      t.string :timezone, null: false, default: 'Asia/Kolkata'
      
      # Base pricing
      t.integer :base_fare_paise, null: false
      t.integer :min_fare_paise, null: false
      t.integer :base_distance_m, null: false, default: 0
      t.integer :per_km_rate_paise, null: false
      
      # Multipliers
      t.decimal :vehicle_multiplier, precision: 6, scale: 3, default: 1.0
      t.decimal :city_multiplier, precision: 6, scale: 3, default: 1.0
      t.decimal :surge_multiplier, precision: 6, scale: 3, default: 1.0
      
      # Variance buffer
      t.decimal :variance_buffer_pct, precision: 6, scale: 3, default: 0.0
      t.integer :variance_buffer_min_paise, default: 0
      t.integer :variance_buffer_max_paise, default: 0
      
      # High-value item handling
      t.integer :high_value_threshold_paise, default: 0
      t.decimal :high_value_buffer_pct, precision: 6, scale: 3, default: 0.0
      t.integer :high_value_buffer_min_paise, default: 0
      
      # Minimum margin guardrail
      t.decimal :min_margin_pct, precision: 6, scale: 3, default: 0.0
      t.integer :min_margin_flat_paise, default: 0
      
      # Versioning and audit
      t.boolean :active, default: true
      t.integer :version, default: 1
      t.datetime :effective_from
      t.datetime :effective_until
      t.bigint :created_by_id
      t.text :notes

      t.timestamps
    end

    add_index :pricing_configs, [:city_code, :vehicle_type, :version], unique: true
    add_index :pricing_configs, [:city_code, :vehicle_type, :active, :effective_from], name: 'idx_pricing_configs_current'

    # Surge pricing rules
    create_table :pricing_surge_rules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :pricing_config_id, null: false
      t.string :rule_type, null: false # 'time_of_day', 'day_of_week', 'traffic_level', 'event_type'
      t.jsonb :condition_json, null: false, default: {}
      t.decimal :multiplier, precision: 6, scale: 3, null: false
      t.integer :priority, default: 100
      t.boolean :active, default: true
      t.bigint :created_by_id
      t.text :notes

      t.timestamps
    end

    add_foreign_key :pricing_surge_rules, :pricing_configs
    add_index :pricing_surge_rules, [:pricing_config_id, :active, :priority], name: 'idx_pricing_surge_rules_active'
    add_index :pricing_surge_rules, :rule_type

    # Pricing quotes (every quote generated)
    create_table :pricing_quotes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :request_id
      t.string :city_code, null: false
      t.string :vehicle_type, null: false
      
      # Coordinates
      t.decimal :pickup_raw_lat, precision: 10, scale: 6
      t.decimal :pickup_raw_lng, precision: 10, scale: 6
      t.decimal :drop_raw_lat, precision: 10, scale: 6
      t.decimal :drop_raw_lng, precision: 10, scale: 6
      t.decimal :pickup_norm_lat, precision: 10, scale: 6
      t.decimal :pickup_norm_lng, precision: 10, scale: 6
      t.decimal :drop_norm_lat, precision: 10, scale: 6
      t.decimal :drop_norm_lng, precision: 10, scale: 6
      
      # Route data
      t.integer :distance_m
      t.integer :duration_s
      t.string :route_provider
      t.string :route_cache_key
      
      # Pricing data
      t.integer :price_paise, null: false
      t.string :price_confidence, default: 'estimated'
      t.string :pricing_version, default: 'v1'
      t.jsonb :breakdown_json, default: {}

      t.timestamps
    end

    add_index :pricing_quotes, :request_id
    add_index :pricing_quotes, :city_code
    add_index :pricing_quotes, :vehicle_type
    add_index :pricing_quotes, :created_at

    # Pricing actuals (feedback loop)
    create_table :pricing_actuals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :pricing_quote_id, null: false
      t.string :vendor, default: 'porter'
      t.string :vendor_booking_ref
      t.integer :actual_price_paise, null: false
      t.text :notes

      t.timestamps
    end

    add_foreign_key :pricing_actuals, :pricing_quotes
    add_index :pricing_actuals, :pricing_quote_id
    add_index :pricing_actuals, :vendor
  end
end
