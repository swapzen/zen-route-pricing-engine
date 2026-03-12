# frozen_string_literal: true

class AddAutoZoneColumnsToZones < ActiveRecord::Migration[8.0]
  def change
    add_column :zones, :auto_generated, :boolean, default: false
    add_column :zones, :generation_version, :integer
    add_column :zones, :cell_count, :integer, default: 0
    add_column :zones, :parent_zone_code, :string
  end
end
