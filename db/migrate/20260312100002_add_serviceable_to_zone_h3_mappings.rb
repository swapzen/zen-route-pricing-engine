# frozen_string_literal: true

class AddServiceableToZoneH3Mappings < ActiveRecord::Migration[8.0]
  def change
    add_column :zone_h3_mappings, :serviceable, :boolean, default: true
  end
end
