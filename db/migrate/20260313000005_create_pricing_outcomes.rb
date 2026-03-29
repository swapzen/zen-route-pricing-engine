# frozen_string_literal: true

class CreatePricingOutcomes < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_outcomes, id: :uuid do |t|
      t.uuid :pricing_quote_id, null: false
      t.string :outcome, null: false
      t.string :city_code, null: false
      t.string :vehicle_type
      t.string :time_band
      t.string :pickup_zone_code
      t.string :drop_zone_code
      t.string :h3_index_r7
      t.integer :quoted_price_paise
      t.integer :response_time_seconds
      t.string :rejection_reason
      t.timestamps
    end

    add_index :pricing_outcomes, :pricing_quote_id
    add_index :pricing_outcomes, [:city_code, :outcome]
    add_index :pricing_outcomes, [:h3_index_r7, :time_band]
  end
end
