# frozen_string_literal: true

class CreatePricingModelTables < ActiveRecord::Migration[8.0]
  def change
    # Model scoring log
    create_table :pricing_model_scores, id: :uuid do |t|
      t.uuid :pricing_quote_id
      t.string :model_version, null: false
      t.string :city_code, null: false
      t.string :vehicle_type
      t.integer :deterministic_price_paise
      t.integer :model_suggested_paise
      t.float :expected_acceptance_pct
      t.float :expected_margin_pct
      t.jsonb :features, default: {}
      t.jsonb :model_metadata, default: {}
      t.string :outcome
      t.timestamps
    end

    add_index :pricing_model_scores, :pricing_quote_id
    add_index :pricing_model_scores, [:model_version, :city_code]

    # Model config (which models are active)
    create_table :pricing_model_configs, id: :uuid do |t|
      t.string :algorithm_name, null: false
      t.string :model_version, null: false
      t.string :mode, default: 'shadow'
      t.integer :canary_pct, default: 0
      t.string :city_code
      t.jsonb :parameters, default: {}
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :pricing_model_configs, [:algorithm_name, :city_code], unique: true
  end
end
