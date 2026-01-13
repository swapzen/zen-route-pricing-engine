# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_01_13_174247) do
  create_table "pricing_actuals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "pricing_quote_id", null: false
    t.string "vendor", default: "porter"
    t.string "vendor_booking_ref"
    t.bigint "actual_price_paise", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pricing_quote_id"], name: "index_pricing_actuals_on_pricing_quote_id"
    t.index ["vendor"], name: "index_pricing_actuals_on_vendor"
  end

  create_table "pricing_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "city_code", null: false
    t.string "vehicle_type", null: false
    t.string "timezone", default: "Asia/Kolkata", null: false
    t.bigint "base_fare_paise", null: false
    t.bigint "min_fare_paise", null: false
    t.bigint "base_distance_m", default: 0, null: false
    t.bigint "per_km_rate_paise", null: false
    t.decimal "vehicle_multiplier", precision: 6, scale: 3, default: "1.0"
    t.decimal "city_multiplier", precision: 6, scale: 3, default: "1.0"
    t.decimal "surge_multiplier", precision: 6, scale: 3, default: "1.0"
    t.decimal "variance_buffer_pct", precision: 6, scale: 3, default: "0.0"
    t.bigint "variance_buffer_min_paise", default: 0
    t.bigint "variance_buffer_max_paise", default: 0
    t.bigint "high_value_threshold_paise", default: 0
    t.decimal "high_value_buffer_pct", precision: 6, scale: 3, default: "0.0"
    t.bigint "high_value_buffer_min_paise", default: 0
    t.decimal "min_margin_pct", precision: 6, scale: 3, default: "0.0"
    t.bigint "min_margin_flat_paise", default: 0
    t.boolean "active", default: true
    t.bigint "version", default: 1
    t.datetime "effective_from"
    t.datetime "effective_until"
    t.bigint "created_by_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city_code", "vehicle_type", "active", "effective_from"], name: "idx_pricing_configs_current"
    t.index ["city_code", "vehicle_type", "version"], name: "idx_on_city_code_vehicle_type_version_008f27eb85", unique: true
  end

  create_table "pricing_quotes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "request_id"
    t.string "city_code", null: false
    t.string "vehicle_type", null: false
    t.decimal "pickup_raw_lat", precision: 10, scale: 6
    t.decimal "pickup_raw_lng", precision: 10, scale: 6
    t.decimal "drop_raw_lat", precision: 10, scale: 6
    t.decimal "drop_raw_lng", precision: 10, scale: 6
    t.decimal "pickup_norm_lat", precision: 10, scale: 6
    t.decimal "pickup_norm_lng", precision: 10, scale: 6
    t.decimal "drop_norm_lat", precision: 10, scale: 6
    t.decimal "drop_norm_lng", precision: 10, scale: 6
    t.bigint "distance_m"
    t.bigint "duration_s"
    t.string "route_provider"
    t.string "route_cache_key"
    t.bigint "price_paise", null: false
    t.string "price_confidence", default: "estimated"
    t.string "pricing_version", default: "v1"
    t.jsonb "breakdown_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city_code"], name: "index_pricing_quotes_on_city_code"
    t.index ["created_at"], name: "index_pricing_quotes_on_created_at"
    t.index ["request_id"], name: "index_pricing_quotes_on_request_id"
    t.index ["vehicle_type"], name: "index_pricing_quotes_on_vehicle_type"
  end

  create_table "pricing_surge_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "pricing_config_id", null: false
    t.string "rule_type", null: false
    t.jsonb "condition_json", default: {}, null: false
    t.decimal "multiplier", precision: 6, scale: 3, null: false
    t.bigint "priority", default: 100
    t.boolean "active", default: true
    t.bigint "created_by_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pricing_config_id", "active", "priority"], name: "idx_pricing_surge_rules_active"
    t.index ["rule_type"], name: "index_pricing_surge_rules_on_rule_type"
  end

  add_foreign_key "pricing_actuals", "pricing_quotes"
  add_foreign_key "pricing_surge_rules", "pricing_configs"
end
