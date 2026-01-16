# frozen_string_literal: true

class AddSpatialGeometryToZones < ActiveRecord::Migration[8.0]
  def up
    # CockroachDB supports GEOGRAPHY type for geospatial data (lat/lng on Earth's surface)
    # This is PostGIS-compatible and supports ST_* functions
    
    # Add polygon column using GEOGRAPHY type
    # GEOGRAPHY is better for real-world lat/lng coordinates
    execute <<-SQL
      ALTER TABLE zones ADD COLUMN IF NOT EXISTS boundary GEOGRAPHY(POLYGON, 4326);
    SQL
    
    # Add center point for quick lookups and circle-based zones
    execute <<-SQL
      ALTER TABLE zones ADD COLUMN IF NOT EXISTS center_point GEOGRAPHY(POINT, 4326);
    SQL
    
    # Add radius for circle-based zones (meters)
    add_column :zones, :radius_m, :integer unless column_exists?(:zones, :radius_m)
    
    # Geometry type: 'bbox' (current), 'polygon', 'circle'
    add_column :zones, :geometry_type, :string, default: 'bbox' unless column_exists?(:zones, :geometry_type)
    
    # Create spatial index for fast point-in-polygon queries
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_zones_boundary_gist ON zones USING GIST (boundary);
    SQL
    
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_zones_center_gist ON zones USING GIST (center_point);
    SQL
    
    add_index :zones, :geometry_type unless index_exists?(:zones, :geometry_type)
  end
  
  def down
    remove_index :zones, :geometry_type if index_exists?(:zones, :geometry_type)
    
    execute "DROP INDEX IF EXISTS idx_zones_boundary_gist"
    execute "DROP INDEX IF EXISTS idx_zones_center_gist"
    
    remove_column :zones, :boundary if column_exists?(:zones, :boundary)
    remove_column :zones, :center_point if column_exists?(:zones, :center_point)
    remove_column :zones, :radius_m if column_exists?(:zones, :radius_m)
    remove_column :zones, :geometry_type if column_exists?(:zones, :geometry_type)
  end
end
