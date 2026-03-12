# frozen_string_literal: true

class CreateVendorRateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :vendor_rate_cards, id: :uuid do |t|
      t.string :vendor_code, null: false
      t.string :city_code, null: false
      t.string :vehicle_type, null: false
      t.string :time_band
      t.bigint :base_fare_paise, null: false
      t.bigint :per_km_rate_paise, null: false
      t.bigint :per_min_rate_paise, default: 0
      t.bigint :dead_km_rate_paise, default: 0
      t.bigint :free_km_m, default: 1000
      t.decimal :surge_cap_multiplier, precision: 4, scale: 2, default: 2.0
      t.bigint :min_fare_paise, null: false
      t.datetime :effective_from, null: false
      t.datetime :effective_until
      t.boolean :active, default: true
      t.bigint :version, default: 1
      t.text :notes

      t.timestamps
    end

    add_index :vendor_rate_cards,
              [:vendor_code, :city_code, :vehicle_type, :time_band, :version],
              unique: true, name: 'idx_vendor_rate_cards_unique'
    add_index :vendor_rate_cards, [:vendor_code, :city_code, :active],
              name: 'idx_vendor_rate_cards_lookup'
  end
end
