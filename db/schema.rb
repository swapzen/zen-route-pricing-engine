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

ActiveRecord::Schema[8.0].define(version: 2026_01_16_034216) do
  create_schema "crdb_internal"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.unique_constraint ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness"
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false

    t.unique_constraint ["key"], name: "index_active_storage_blobs_on_key"
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false

    t.unique_constraint ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness"
  end

  create_table "address_contacts", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "location_id", null: false
    t.string "full_name"
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_address_contacts_on_location_id"
  end

  create_table "admin_coin_overrides", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.decimal "adjusted_coin_balance", precision: 10, scale: 2, default: "0.0"
    t.text "reason"
    t.string "admin_user"
    t.decimal "start_balance", precision: 10, scale: 2, default: "0.0"
    t.decimal "final_balance", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_admin_coin_overrides_on_user_id"
  end

  create_table "admins", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "role"
    t.boolean "active", default: true, null: false
    t.bigint "zone_id"
    t.string "password_digest"
    t.string "password", default: "", null: false
    t.string "password_confirmation"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_admins_on_active"
    t.index ["phone"], name: "index_admins_on_phone"
    t.index ["role"], name: "index_admins_on_role"
    t.index ["zone_id"], name: "index_admins_on_zone_id"
    t.unique_constraint ["email"], name: "index_admins_on_email"
  end

  create_table "attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "attachable_type", null: false
    t.uuid "attachable_id", null: false
    t.string "file_url", null: false
    t.string "file_type", null: false
    t.bigint "position"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "ready", null: false
    t.uuid "active_storage_blob_id"
    t.index ["active_storage_blob_id"], name: "index_attachments_on_active_storage_blob_id"
    t.index ["attachable_type", "attachable_id", "status"], name: "index_attachments_on_attachable_and_status"
    t.index ["attachable_type", "attachable_id"], name: "index_attachments_on_attachable"
    t.index ["file_type"], name: "index_attachments_on_file_type"
    t.unique_constraint ["attachable_type", "attachable_id", "position"], name: "index_attachments_on_attachable_and_position"
  end

  create_table "blocked_users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "blocker_id", null: false
    t.bigint "blocked_id", null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_blocked_users_on_blocked_id"
    t.index ["blocker_id"], name: "index_blocked_users_on_blocker_id"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.uuid "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_categories_on_parent_id"
    t.unique_constraint ["slug"], name: "index_categories_on_slug"
  end

  create_table "category_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id", null: false
    t.string "locale", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "coin_earning_rules", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "activity_type"
    t.bigint "coins_earned"
    t.string "user_type"
    t.text "criteria"
    t.string "status"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_coin_earning_rules_on_user_id"
  end

  create_table "coin_expiry_settings", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "coin_type", default: "referral_coin"
    t.bigint "expiry_period"
    t.string "status"
    t.datetime "awarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "coin_type"], name: "index_coin_expiry_settings_on_user_id_and_coin_type"
    t.index ["user_id"], name: "index_coin_expiry_settings_on_user_id"
  end

  create_table "delivery_partners", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "name"
    t.string "contact_info"
    t.string "service_area"
    t.text "service_types"
    t.text "cost_structure"
    t.string "delivery_speed"
    t.text "performance_metrics"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "feature_flags", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "enabled", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "fraud_rules", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "rule_name"
    t.text "description"
    t.boolean "active"
    t.decimal "threshold_value"
    t.string "flag_action"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "give_away_claims", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "listing_id", null: false
    t.uuid "owner_id", null: false
    t.uuid "claimer_id", null: false
    t.string "pickup_type", default: "self_pickup", null: false
    t.uuid "delivery_address_id"
    t.string "status", default: "pending", null: false
    t.boolean "pickup_confirmed_by_claimer", default: false, null: false
    t.boolean "pickup_confirmed_by_owner", default: false, null: false
    t.string "note"
    t.datetime "approved_at", precision: nil
    t.datetime "rejected_at", precision: nil
    t.datetime "cancelled_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claimer_id", "status", "created_at"], name: "index_give_away_claims_on_claimer_id_and_status_and_created_at", order: { created_at: :desc }
    t.index ["listing_id", "status"], name: "index_give_away_claims_on_listing_id_and_status"
    t.index ["owner_id", "status", "created_at"], name: "index_give_away_claims_on_owner_id_and_status_and_created_at", order: { created_at: :desc }
    t.check_constraint "(pickup_type IN ('self_pickup'::STRING, 'swapzen_delivery'::STRING))", name: "chk_pickup_type_valid"
    t.check_constraint "(status IN ('pending'::STRING, 'approved'::STRING, 'rejected'::STRING, 'cancelled'::STRING, 'completed'::STRING))", name: "chk_status_valid"
    t.unique_constraint ["listing_id", "claimer_id"], name: "idx_give_away_unique_active_claim"
  end

  create_table "listing_approval_settings", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.boolean "manual_approval_required"
    t.boolean "auto_approval_enabled"
    t.bigint "max_items_per_user"
    t.text "approval_criteria"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_id"], name: "index_listing_approval_settings_on_zone_id"
  end

  create_table "listing_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "listing_id", null: false
    t.string "name", null: false
    t.uuid "category_id", null: false
    t.string "condition", null: false
    t.string "usage_duration"
    t.boolean "requires_dismantling", default: false
    t.string "delivery_vehicle_type"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_listing_items_on_category_id"
    t.index ["listing_id", "category_id"], name: "index_listing_items_on_listing_and_category"
    t.index ["listing_id"], name: "index_listing_items_on_listing_id"
  end

  create_table "listing_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.unique_constraint ["name"], name: "index_listing_types_on_name"
  end

  create_table "listings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "listing_type_id", null: false
    t.string "title"
    t.text "description"
    t.uuid "item_location_id"
    t.uuid "pickup_location_id"
    t.string "delivery_type"
    t.string "status", default: "draft", null: false
    t.boolean "approved", default: false
    t.string "rejection_reason_code"
    t.text "rejection_reason_text"
    t.uuid "reviewed_by_id"
    t.datetime "reviewed_at", precision: nil
    t.boolean "swap_completed", default: false
    t.datetime "swap_completed_at", precision: nil
    t.uuid "swap_request_id"
    t.uuid "giveaway_claim_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "zone_location_id"
    t.index ["listing_type_id", "status", "created_at"], name: "index_listings_on_listing_type_status"
    t.index ["user_id", "status"], name: "index_listings_on_user_id_and_status"
    t.index ["user_id"], name: "index_listings_on_user_id"
    t.index ["zone_location_id"], name: "index_listings_on_zone_location_id"
  end

  create_table "locations", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "user_id"
    t.text "address_line"
    t.decimal "latitude"
    t.decimal "longitude"
    t.string "city"
    t.string "state"
    t.string "country"
    t.string "pin_code"
    t.boolean "is_primary", default: false
    t.string "location_type", default: "home"
    t.string "address_line_2"
    t.string "formatted_address"
    t.boolean "is_default", default: false
    t.string "location_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_locations_on_user_id"
    t.unique_constraint ["user_id"], name: "uniq_locations_primary_per_user"
  end

  create_table "otp_codes", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "phone"
    t.string "otp_code", null: false
    t.datetime "expires_at"
    t.boolean "verified", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "email"
    t.index ["email"], name: "index_otp_codes_on_email"
    t.index ["phone"], name: "index_otp_codes_on_phone"
    t.index ["user_id"], name: "index_otp_codes_on_user_id"
  end

  create_table "pickup_slots", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_delivery_config_id", null: false
    t.bigint "delivery_partner_id", null: false
    t.string "pickup_day"
    t.time "start_time"
    t.time "end_time"
    t.boolean "available"
    t.bigint "max_capacity"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_partner_id"], name: "index_pickup_slots_on_delivery_partner_id"
    t.index ["zone_delivery_config_id"], name: "index_pickup_slots_on_zone_delivery_config_id"
  end

  create_table "platforms", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.decimal "platform_fee"
    t.decimal "gst_rate"
    t.boolean "escrow_enabled"
    t.string "currency_code"
    t.string "locale"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "preferred_exchange_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "listing_id", null: false
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.unique_constraint ["listing_id", "category_id"], name: "index_preferred_exchange_on_listing_and_category"
  end

  create_table "premium_feature_flags", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "enabled", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

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
    t.string "vendor_vehicle_code"
    t.bigint "weight_capacity_kg"
    t.string "display_name"
    t.text "description"
    t.index ["city_code", "vehicle_type", "active", "effective_from"], name: "idx_pricing_configs_current"
    t.index ["vendor_vehicle_code", "city_code"], name: "index_pricing_configs_on_vendor_code_and_city"
    t.unique_constraint ["city_code", "vehicle_type", "version"], name: "idx_on_city_code_vehicle_type_version_008f27eb85"
  end

  create_table "pricing_distance_slabs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "pricing_config_id", null: false
    t.bigint "min_distance_m", default: 0, null: false
    t.bigint "max_distance_m"
    t.bigint "per_km_rate_paise", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pricing_config_id"], name: "index_pricing_distance_slabs_on_pricing_config_id"
    t.unique_constraint ["pricing_config_id", "min_distance_m"], name: "idx_slabs_config_min_distance"
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

  create_table "pricing_zone_multipliers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "zone_code", null: false
    t.string "zone_name"
    t.string "city_code", default: "hyd"
    t.decimal "lat_min", precision: 10, scale: 6
    t.decimal "lat_max", precision: 10, scale: 6
    t.decimal "lng_min", precision: 10, scale: 6
    t.decimal "lng_max", precision: 10, scale: 6
    t.decimal "multiplier", precision: 4, scale: 2, default: "1.0"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "small_vehicle_mult", precision: 4, scale: 2, default: "1.0", comment: "Multiplier for 2W/Scooter/Mini3W"
    t.decimal "mid_truck_mult", precision: 4, scale: 2, default: "1.0", comment: "Multiplier for 3W/TataAce/Pickup8ft"
    t.decimal "heavy_truck_mult", precision: 4, scale: 2, default: "1.0", comment: "Multiplier for Eeco/Tata407/Canter"
    t.string "zone_type", comment: "Business zone classification"
    t.jsonb "metadata", default: {}, comment: "Extensible metadata for zone-specific features"
    t.index ["lat_min", "lat_max", "lng_min", "lng_max"], name: "idx_zone_coords"
    t.index ["zone_type"], name: "index_pricing_zone_multipliers_on_zone_type"
    t.unique_constraint ["city_code", "zone_code"], name: "index_pricing_zone_multipliers_on_city_code_and_zone_code"
  end

  create_table "profile_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "preferences", default: {}
    t.string "app_language"
    t.boolean "dark_mode_enabled", default: false
    t.boolean "notification_enabled", default: true
    t.string "locale", default: "en"
    t.string "theme_preference", default: "light"
    t.string "user_status", default: "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_profile_settings_on_user_id"
  end

  create_table "prohibited_keywords", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "keyword"
    t.string "category"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "referral_rewards", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "referred_user_id", null: false
    t.bigint "coins_earned"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["referred_user_id"], name: "index_referral_rewards_on_referred_user_id"
    t.index ["user_id"], name: "index_referral_rewards_on_user_id"
    t.unique_constraint ["user_id", "referred_user_id"], name: "index_referral_rewards_on_user_id_and_referred_user_id"
  end

  create_table "referral_rules", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.bigint "referral_code_reward"
    t.bigint "referee_reward"
    t.bigint "referral_limit"
    t.string "status", default: "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_id"], name: "index_referral_rules_on_zone_id"
  end

  create_table "swap_counters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "swap_request_id", null: false
    t.bigint "version", null: false
    t.string "author_role", null: false
    t.string "counter_type", null: false
    t.string "diff_hint"
    t.jsonb "requester_item_ids", default: [], null: false
    t.jsonb "owner_item_ids", default: [], null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "coins", precision: 12, scale: 4, default: "0.0"
    t.string "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id", null: false
    t.index ["created_by_id"], name: "index_swap_counters_on_created_by_id"
    t.index ["owner_item_ids"], name: "idx_swap_counters_owner_item_ids", using: :gin
    t.index ["requester_item_ids"], name: "idx_swap_counters_requester_item_ids", using: :gin
    t.index ["swap_request_id", "created_at"], name: "index_swap_counters_on_swap_request_id_and_created_at"
    t.check_constraint "((jsonb_typeof(owner_item_ids) = 'array'::STRING) AND (jsonb_array_length(owner_item_ids) <= 10))", name: "chk_owner_items_size"
    t.check_constraint "((jsonb_typeof(requester_item_ids) = 'array'::STRING) AND (jsonb_array_length(requester_item_ids) <= 10))", name: "chk_requester_items_size"
    t.unique_constraint ["swap_request_id", "version"], name: "index_swap_counters_on_swap_request_id_and_version"
  end

  create_table "swap_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "requester_listing_id"
    t.string "swap_type", null: false
    t.string "status", default: "pending", null: false
    t.string "currency_code", default: "INR", null: false
    t.string "note"
    t.decimal "initial_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "initial_coins", precision: 12, scale: 4, default: "0.0"
    t.bigint "current_offer_version", default: 1, null: false
    t.decimal "current_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "current_coins", precision: 12, scale: 4, default: "0.0"
    t.bigint "accepted_version"
    t.decimal "accepted_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "accepted_coins", precision: 12, scale: 4, default: "0.0"
    t.jsonb "accepted_items", default: {}, null: false
    t.string "last_action_by"
    t.datetime "last_action_at", precision: nil
    t.datetime "accepted_at", precision: nil
    t.datetime "rejected_at", precision: nil
    t.datetime "cancelled_at", precision: nil
    t.string "state_reason"
    t.jsonb "owner_listing_snapshot", default: {}, null: false
    t.jsonb "requester_listing_snapshot", default: {}, null: false
    t.bigint "negotiation_cap", default: 25, null: false
    t.boolean "unread_for_owner", default: false, null: false
    t.boolean "unread_for_requester", default: false, null: false
    t.uuid "chat_thread_id"
    t.bigint "lock_version", default: 0, null: false
    t.datetime "expires_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "owner_listing_id", null: false
    t.jsonb "initial_items", default: {}, null: false
    t.jsonb "current_items", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "accepted_by_id"
    t.string "accepted_by_role"
    t.bigint "counters_count", default: 0, null: false
    t.bigint "owner_id", null: false
    t.bigint "requester_id", null: false
    t.index ["accepted_items"], name: "idx_swap_requests_accepted_items", using: :gin
    t.index ["current_items"], name: "idx_swap_requests_current_items_inverted", using: :gin
    t.index ["initial_items"], name: "idx_swap_requests_initial_items_inverted", using: :gin
    t.index ["owner_id", "status", "created_at"], name: "index_swap_requests_on_owner_id_and_status_and_created_at", order: { created_at: :desc }
    t.index ["owner_id", "status", "updated_at", "currency_code", "current_amount", "current_coins", "counters_count", "owner_listing_id", "requester_listing_id", "swap_type"], name: "idx_owner_status_updated", order: { updated_at: :desc }
    t.index ["owner_listing_id"], name: "index_swap_requests_on_owner_listing_id"
    t.index ["requester_id", "status", "created_at"], name: "index_swap_requests_on_requester_id_and_status_and_created_at", order: { created_at: :desc }
    t.index ["requester_id", "status", "updated_at", "currency_code", "current_amount", "current_coins", "counters_count", "owner_listing_id", "requester_listing_id", "swap_type"], name: "idx_requester_status_updated", order: { updated_at: :desc }
    t.index ["status", "last_action_at"], name: "index_swap_requests_on_status_and_last_action_at", order: { last_action_at: :desc }
    t.check_constraint "(((initial_amount >= 0) AND (current_amount >= 0)) AND (accepted_amount >= 0))", name: "chk_amount_nonneg"
    t.check_constraint "(((initial_coins >= 0) AND (current_coins >= 0)) AND (accepted_coins >= 0))", name: "chk_coins_nonneg"
    t.unique_constraint ["owner_listing_id", "requester_listing_id"], name: "ux_open_pair_once"
    t.unique_constraint ["owner_listing_id"], name: "ux_one_accepted_per_owner_listing"
  end

  create_table "swap_timeline_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "swap_request_id", null: false
    t.string "event_type", null: false
    t.string "channel", default: "system", null: false
    t.uuid "actor_id"
    t.bigint "version"
    t.jsonb "metadata", default: {}, null: false
    t.boolean "read_by_owner", default: false, null: false
    t.boolean "read_by_requester", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["swap_request_id", "created_at"], name: "index_swap_timeline_events_on_swap_request_id_and_created_at"
  end

  create_table "user_devices", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "device_type"
    t.string "device_token"
    t.string "os_type"
    t.string "os_version"
    t.string "app_version"
    t.datetime "last_active_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_devices_on_user_id"
  end

  create_table "user_login_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "device_type"
    t.string "browser_info"
    t.datetime "login_at"
    t.string "status", default: "failed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_login_logs_on_user_id"
  end

  create_table "users", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "password_digest"
    t.bigint "status"
    t.uuid "current_location_id"
    t.uuid "country_id"
    t.uuid "region_id"
    t.uuid "zone_location_id"
    t.string "locale"
    t.string "currency_pref"
    t.datetime "last_login_at"
    t.string "referral_code"
    t.bigint "zone_id"
    t.string "subscription_type"
    t.string "first_name"
    t.string "last_name"
    t.date "date_of_birth"
    t.string "gender"
    t.text "bio"
    t.boolean "email_verified", default: false
    t.boolean "phone_verified", default: false
    t.jsonb "notification_preferences"
    t.string "theme_preference", default: "light"
    t.string "language_preference", default: "en"
    t.bigint "swaps_count", default: 0
    t.datetime "last_swap_at"
    t.string "role", default: "user"
    t.string "account_type", default: "basic"
    t.uuid "referred_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_confirmation"
    t.boolean "agreed_tos_privacy_policy", default: false, null: false
    t.string "password", default: "", null: false
    t.string "interests", default: [], array: true
    t.index ["phone"], name: "index_users_on_phone"
    t.index ["zone_id"], name: "index_users_on_zone_id"
    t.unique_constraint ["email"], name: "index_users_on_email"
    t.unique_constraint ["referral_code"], name: "index_users_on_referral_code"
  end

  create_table "zone_announcements", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "announcement_type"
    t.string "status", default: "active"
    t.datetime "valid_from"
    t.datetime "valid_until"
    t.text "message"
    t.jsonb "user_targeting", default: {}
    t.uuid "zone_ids", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "zone_category_restrictions", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_listing_rule_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_listing_rule_id"], name: "index_zone_category_restrictions_on_zone_listing_rule_id"
  end

  create_table "zone_delivery_configs", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.bigint "delivery_partner_id", null: false
    t.jsonb "fee_table"
    t.bigint "sla_hours"
    t.boolean "self_pickup_enabled"
    t.boolean "courier_delivery_enabled"
    t.boolean "expedited_delivery_enabled"
    t.bigint "max_delivery_time"
    t.float "delivery_cost_multiplier"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_partner_id"], name: "index_zone_delivery_configs_on_delivery_partner_id"
    t.index ["zone_id"], name: "index_zone_delivery_configs_on_zone_id"
  end

  create_table "zone_distance_slabs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "city_code", null: false
    t.bigint "zone_id", null: false
    t.string "vehicle_type", null: false
    t.bigint "min_distance_m", default: 0, null: false
    t.bigint "max_distance_m"
    t.bigint "per_km_rate_paise", null: false
    t.bigint "flat_fare_paise"
    t.bigint "priority", default: 10
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city_code", "active"], name: "index_zone_distance_slabs_on_city_code_and_active"
    t.index ["zone_id", "vehicle_type", "active"], name: "idx_on_zone_id_vehicle_type_active_a11cdf01f8"
    t.index ["zone_id"], name: "index_zone_distance_slabs_on_zone_id"
    t.unique_constraint ["city_code", "zone_id", "vehicle_type", "min_distance_m"], name: "idx_zone_slabs_unique"
  end

  create_table "zone_listing_rules", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.bigint "max_items_per_user"
    t.boolean "swap_enabled"
    t.boolean "monetary_swap_enabled"
    t.boolean "premium_listing_enabled"
    t.boolean "approval_required"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_id"], name: "index_zone_listing_rules_on_zone_id"
  end

  create_table "zone_locations", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.string "name"
    t.string "pincode"
    t.decimal "lattitude"
    t.string "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_id"], name: "index_zone_locations_on_zone_id"
  end

  create_table "zone_pair_vehicle_pricings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "city_code", null: false
    t.bigint "from_zone_id", null: false
    t.bigint "to_zone_id", null: false
    t.string "vehicle_type", null: false
    t.bigint "base_fare_paise"
    t.bigint "min_fare_paise"
    t.bigint "per_km_rate_paise"
    t.string "corridor_type"
    t.boolean "directional", default: true
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "time_band"
    t.index ["from_zone_id"], name: "index_zone_pair_vehicle_pricings_on_from_zone_id"
    t.index ["to_zone_id"], name: "index_zone_pair_vehicle_pricings_on_to_zone_id"
    t.unique_constraint ["city_code", "from_zone_id", "to_zone_id", "vehicle_type", "time_band"], name: "idx_zpvp_routing_with_time_band"
  end

  create_table "zone_policies", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.string "feature"
    t.boolean "enabled"
    t.datetime "start_date"
    t.datetime "end_date"
    t.uuid "updated_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_id"], name: "index_zone_policies_on_zone_id"
  end

  create_table "zone_vehicle_pricings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "zone_id", null: false
    t.string "city_code", null: false
    t.string "vehicle_type", null: false
    t.bigint "base_fare_paise", null: false
    t.bigint "min_fare_paise", null: false
    t.bigint "base_distance_m", null: false
    t.bigint "per_km_rate_paise", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_id"], name: "index_zone_vehicle_pricings_on_zone_id"
    t.unique_constraint ["city_code", "zone_id", "vehicle_type"], name: "idx_zvp_lookup"
  end

  create_table "zone_vehicle_time_pricings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "zone_vehicle_pricing_id", null: false
    t.string "time_band", null: false
    t.bigint "base_fare_paise", null: false
    t.bigint "min_fare_paise", null: false
    t.bigint "per_km_rate_paise", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zone_vehicle_pricing_id"], name: "index_zone_vehicle_time_pricings_on_zone_vehicle_pricing_id"
    t.unique_constraint ["zone_vehicle_pricing_id", "time_band"], name: "idx_zvtp_pricing_time"
  end

# Could not dump table "zones" because of following StandardError
#   Unknown type 'geography' for column 'boundary'


  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "address_contacts", "locations"
  add_foreign_key "admin_coin_overrides", "users"
  add_foreign_key "admins", "zones"
  add_foreign_key "blocked_users", "users", column: "blocked_id"
  add_foreign_key "blocked_users", "users", column: "blocker_id"
  add_foreign_key "coin_earning_rules", "users"
  add_foreign_key "coin_expiry_settings", "users"
  add_foreign_key "listing_approval_settings", "zones"
  add_foreign_key "listing_items", "categories"
  add_foreign_key "listing_items", "listings", on_delete: :cascade
  add_foreign_key "listings", "users"
  add_foreign_key "listings", "zone_locations"
  add_foreign_key "locations", "users", validate: false
  add_foreign_key "otp_codes", "users"
  add_foreign_key "pickup_slots", "delivery_partners"
  add_foreign_key "pickup_slots", "zone_delivery_configs"
  add_foreign_key "preferred_exchange_categories", "categories"
  add_foreign_key "preferred_exchange_categories", "listings", on_delete: :cascade
  add_foreign_key "pricing_actuals", "pricing_quotes"
  add_foreign_key "pricing_distance_slabs", "pricing_configs"
  add_foreign_key "pricing_surge_rules", "pricing_configs"
  add_foreign_key "profile_settings", "users"
  add_foreign_key "referral_rewards", "users"
  add_foreign_key "referral_rewards", "users", column: "referred_user_id"
  add_foreign_key "referral_rules", "zones"
  add_foreign_key "user_devices", "users"
  add_foreign_key "user_login_logs", "users"
  add_foreign_key "users", "zones"
  add_foreign_key "zone_category_restrictions", "zone_listing_rules"
  add_foreign_key "zone_delivery_configs", "delivery_partners"
  add_foreign_key "zone_delivery_configs", "zones"
  add_foreign_key "zone_distance_slabs", "zones"
  add_foreign_key "zone_listing_rules", "zones"
  add_foreign_key "zone_locations", "zones"
  add_foreign_key "zone_pair_vehicle_pricings", "zones", column: "from_zone_id"
  add_foreign_key "zone_pair_vehicle_pricings", "zones", column: "to_zone_id"
  add_foreign_key "zone_policies", "zones"
  add_foreign_key "zone_vehicle_pricings", "zones"
  add_foreign_key "zone_vehicle_time_pricings", "zone_vehicle_pricings"
end
