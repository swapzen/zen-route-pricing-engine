# frozen_string_literal: true

class AddH3IndexesToZones < ActiveRecord::Migration[8.0]
  def change
    add_column :zones, :h3_indexes_r7, :string, array: true, default: []
    add_column :zones, :h3_indexes_r9, :string, array: true, default: []
  end
end
