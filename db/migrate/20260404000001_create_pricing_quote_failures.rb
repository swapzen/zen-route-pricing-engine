# frozen_string_literal: true

class CreatePricingQuoteFailures < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_quote_failures do |t|
      t.string :city_code, null: false
      t.string :vehicle_type
      t.string :request_id
      t.decimal :pickup_lat, precision: 10, scale: 7
      t.decimal :pickup_lng, precision: 10, scale: 7
      t.decimal :drop_lat, precision: 10, scale: 7
      t.decimal :drop_lng, precision: 10, scale: 7
      t.string :pickup_h3_r7
      t.string :drop_h3_r7
      t.string :failure_code, null: false     # zone_not_found | no_config | route_failed | other
      t.string :error_message
      t.integer :http_status
      t.jsonb :context, default: {}
      t.timestamps
    end

    add_index :pricing_quote_failures, :city_code
    add_index :pricing_quote_failures, :failure_code
    add_index :pricing_quote_failures, :created_at
    add_index :pricing_quote_failures, :pickup_h3_r7
  end
end
