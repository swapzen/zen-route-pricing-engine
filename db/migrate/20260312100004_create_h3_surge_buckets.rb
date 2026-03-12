# frozen_string_literal: true

class CreateH3SurgeBuckets < ActiveRecord::Migration[8.0]
  def change
    create_table :h3_surge_buckets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :h3_index,         null: false  # Res 9 hex index (hex string)
      t.string   :city_code,        null: false
      t.integer  :h3_resolution,    null: false, default: 9
      t.float    :demand_score,     default: 0.0   # 0-100 scale
      t.float    :supply_score,     default: 0.0   # 0-100 scale
      t.float    :surge_multiplier, default: 1.0   # 1.0 = no surge
      t.string   :time_band                        # morning/afternoon/evening or nil for all
      t.datetime :expires_at                        # TTL for real-time surge
      t.string   :source                            # 'manual', 'algorithm', 'event'
      t.jsonb    :metadata, default: {}             # Flexible metadata (event name, reason, etc.)
      t.timestamps
    end

    add_index :h3_surge_buckets, [:city_code, :h3_index, :time_band], unique: true, name: 'idx_surge_city_hex_band'
    add_index :h3_surge_buckets, [:city_code, :h3_resolution]
    add_index :h3_surge_buckets, :expires_at
  end
end
