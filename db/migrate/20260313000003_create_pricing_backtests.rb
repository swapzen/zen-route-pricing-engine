# frozen_string_literal: true

class CreatePricingBacktests < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_backtests, id: :uuid do |t|
      t.string :city_code, null: false
      t.uuid :candidate_config_id
      t.uuid :baseline_config_id
      t.string :status, default: 'pending'
      t.integer :sample_size
      t.integer :completed_replays, default: 0
      t.jsonb :results, default: {}
      t.jsonb :replay_details, default: []
      t.string :triggered_by
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :pricing_backtests, [:city_code, :status]
  end
end
