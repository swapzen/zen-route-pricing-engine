# frozen_string_literal: true

class CreateMerchantPricingPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :merchant_pricing_policies, id: :uuid do |t|
      t.string :merchant_id, null: false
      t.string :merchant_name
      t.string :city_code
      t.string :vehicle_type
      t.string :policy_type, null: false
      t.integer :value_paise
      t.float :value_pct
      t.integer :priority, default: 0
      t.boolean :active, default: true
      t.date :effective_from
      t.date :effective_until
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :merchant_pricing_policies, [:merchant_id, :active]
    add_index :merchant_pricing_policies, [:city_code, :vehicle_type]
  end
end
