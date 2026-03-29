# frozen_string_literal: true

class AddBoundaryGeojsonToZones < ActiveRecord::Migration[8.0]
  def change
    # JSONB avoids the CockroachDB schema.rb GEOGRAPHY dump issue
    add_column :zones, :boundary_geojson, :jsonb
    add_column :zones, :center_lat, :decimal, precision: 10, scale: 7
    add_column :zones, :center_lng, :decimal, precision: 10, scale: 7
  end
end
