# frozen_string_literal: true

class CreateControlPlaneTables < ActiveRecord::Migration[8.0]
  def change
    # 1. Change log (audit trail)
    create_table :pricing_change_logs, id: :uuid do |t|
      t.string :entity_type, null: false
      t.uuid :entity_id, null: false
      t.string :action, null: false
      t.string :actor, null: false
      t.jsonb :before_state, default: {}
      t.jsonb :after_state, default: {}
      t.jsonb :diff, default: {}
      t.string :city_code
      t.timestamps
    end

    add_index :pricing_change_logs, [:entity_type, :entity_id]
    add_index :pricing_change_logs, :city_code

    # 2. Rollout flags (feature gates)
    create_table :pricing_rollout_flags, id: :uuid do |t|
      t.string :flag_name, null: false
      t.string :city_code
      t.boolean :enabled, default: false
      t.integer :rollout_pct, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :pricing_rollout_flags, [:flag_name, :city_code], unique: true

    # 3. Emergency freeze
    create_table :pricing_emergency_freezes, id: :uuid do |t|
      t.string :city_code
      t.string :reason, null: false
      t.string :activated_by, null: false
      t.string :deactivated_by
      t.datetime :activated_at, null: false
      t.datetime :deactivated_at
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :pricing_emergency_freezes, [:city_code, :active]
  end
end
