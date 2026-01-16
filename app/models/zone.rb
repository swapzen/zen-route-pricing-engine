class Zone < ApplicationRecord
  # Existing columns: name, city, status (bool)
  # Enhanced columns: zone_code, zone_type, lat/lng bounds, metadata
  # Spatial columns: boundary (GEOGRAPHY POLYGON), center_point (GEOGRAPHY POINT), radius_m
  # Industry-standard pricing columns (Cogoport/ShipX patterns):
  #   - fuel_surcharge_pct: FSC % override for this zone
  #   - zone_multiplier: SLS multiplier for this zone type (1.0 = neutral)
  #   - is_oda: Out of Delivery Area flag
  #   - special_location_surcharge_paise: Flat fee for special locations (airports, tech parks)
  #   - oda_surcharge_pct: Extra % when both pickup & drop are ODA
  
  has_many :zone_vehicle_pricings, dependent: :destroy
  has_many :zone_distance_slabs, dependent: :destroy
  
  # Zone Pairs (both directions)
  has_many :outgoing_pair_pricings, class_name: 'ZonePairVehiclePricing', foreign_key: 'from_zone_id', dependent: :destroy
  has_many :incoming_pair_pricings, class_name: 'ZonePairVehiclePricing', foreign_key: 'to_zone_id', dependent: :destroy

  validates :zone_code, presence: true, uniqueness: { scope: :city }
  validates :city, presence: true
  validates :zone_type, presence: true

  scope :active, -> { where(status: true) }
  scope :for_city, ->(city_code) { where('LOWER(city) = LOWER(?)', city_code) }
  scope :oda, -> { where(is_oda: true) }
  
  # =========================================================================
  # ZONE TYPES & DEFAULTS
  # =========================================================================
  ZONE_TYPES = %w[
    tech_corridor
    business_cbd
    airport_logistics
    residential_growth
    industrial
    outer_ring
    default
  ].freeze
  
  # Default multipliers by zone type (used if zone_multiplier not set)
  DEFAULT_ZONE_MULTIPLIERS = {
    'tech_corridor'      => 1.00,  # Competitive pricing for tech hubs
    'business_cbd'       => 1.05,  # Premium for CBD (congestion, parking)
    'airport_logistics'  => 1.10,  # Long-haul premium
    'residential_growth' => 0.95,  # Discount to encourage adoption
    'industrial'         => 0.95,  # Volume discount
    'outer_ring'         => 1.00,  # Neutral
    'default'            => 1.00
  }.freeze
  
  # Effective zone multiplier (uses configured value or default by type)
  def effective_zone_multiplier
    zone_multiplier.presence || DEFAULT_ZONE_MULTIPLIERS[zone_type] || 1.0
  end
  
  # Effective fuel surcharge % for this zone
  def effective_fuel_surcharge_pct
    fuel_surcharge_pct.presence || 0.0
  end
  
  # Effective ODA surcharge % for this zone
  def effective_oda_surcharge_pct
    oda_surcharge_pct.presence || 5.0
  end
  
  # Geometry types
  GEOMETRY_TYPES = %w[bbox polygon circle].freeze
  
  # =========================================================================
  # SPATIAL QUERIES (CockroachDB/PostGIS compatible)
  # =========================================================================
  
  # Find zone containing a point
  # Currently uses bbox (bounding box) approach
  # TODO: Enable spatial queries when CockroachDB spatial is properly configured
  def self.find_containing(city_code, lat, lng)
    # For now, use simple bbox lookup (works with all DBs)
    for_city(city_code).active
      .order(priority: :desc)
      .find { |z| z.contains_point?(lat, lng) }
  end
  
  # Check if point is in zone
  # Currently uses bbox (bounding box) - simple and fast
  # TODO: Add polygon/circle support when CockroachDB spatial is configured
  def contains_point?(lat, lng)
    # Use bbox for all geometry types for now
    contains_point_bbox?(lat, lng)
  end
  
  # Bounding box check (original implementation)
  def contains_point_bbox?(lat, lng)
    return false unless lat_min && lat_max && lng_min && lng_max
    
    lat = lat.to_f
    lng = lng.to_f
    
    lat >= lat_min && lat <= lat_max &&
      lng >= lng_min && lng <= lng_max
  end
  
  # Polygon check using CockroachDB spatial
  def contains_point_polygon?(lat, lng)
    return contains_point_bbox?(lat, lng) unless boundary.present?
    
    point_wkt = "POINT(#{lng} #{lat})"
    Zone.where(id: id)
        .where("ST_Contains(boundary::geometry, ST_GeomFromText(?, 4326))", point_wkt)
        .exists?
  end
  
  # Circle check using CockroachDB spatial
  def contains_point_circle?(lat, lng)
    return contains_point_bbox?(lat, lng) unless center_point.present? && radius_m.present?
    
    point_wkt = "POINT(#{lng} #{lat})"
    Zone.where(id: id)
        .where("ST_DWithin(center_point, ST_GeomFromText(?, 4326)::geography, radius_m)", point_wkt)
        .exists?
  end
  
  # =========================================================================
  # POLYGON HELPERS
  # =========================================================================
  
  # Set polygon from array of [lat, lng] coordinates
  # Polygon must be closed (first point = last point)
  def set_polygon(coords)
    return if coords.blank? || coords.length < 3
    
    # Ensure polygon is closed
    coords = coords.dup
    coords << coords.first unless coords.first == coords.last
    
    # Convert to WKT format (lng, lat order for PostGIS)
    wkt_coords = coords.map { |lat, lng| "#{lng} #{lat}" }.join(', ')
    wkt = "POLYGON((#{wkt_coords}))"
    
    self.geometry_type = 'polygon'
    update_column(:boundary, Arel.sql("ST_GeomFromText('#{wkt}', 4326)::geography"))
    
    # Also set center point for quick lookups
    set_center_from_polygon(coords)
  end
  
  # Set circle zone (center + radius in meters)
  def set_circle(center_lat, center_lng, radius_meters)
    point_wkt = "POINT(#{center_lng} #{center_lat})"
    
    self.geometry_type = 'circle'
    self.radius_m = radius_meters
    update_column(:center_point, Arel.sql("ST_GeomFromText('#{point_wkt}', 4326)::geography"))
  end
  
  # Calculate center from polygon coordinates
  def set_center_from_polygon(coords)
    return if coords.blank?
    
    avg_lat = coords.map(&:first).sum / coords.length.to_f
    avg_lng = coords.map(&:last).sum / coords.length.to_f
    
    point_wkt = "POINT(#{avg_lng} #{avg_lat})"
    update_column(:center_point, Arel.sql("ST_GeomFromText('#{point_wkt}', 4326)::geography"))
  end
  
  # Get polygon coordinates as array (for display/export)
  def polygon_coords
    return nil unless boundary.present?
    
    # Query to extract coordinates from boundary
    result = Zone.connection.execute(
      "SELECT ST_AsText(boundary) FROM zones WHERE id = #{id}"
    ).first
    
    return nil unless result && result['st_astext']
    
    # Parse WKT: POLYGON((lng lat, lng lat, ...))
    wkt = result['st_astext']
    return nil unless wkt.start_with?('POLYGON')
    
    coords_str = wkt.gsub(/POLYGON\(\(|\)\)/, '')
    coords_str.split(',').map do |pair|
      lng, lat = pair.strip.split(' ').map(&:to_f)
      [lat, lng]  # Return as [lat, lng]
    end
  rescue StandardError
    nil
  end
  
  # =========================================================================
  # ZONE SLABS
  # =========================================================================
  
  # Get distance slabs for this zone and vehicle type
  def slabs_for_vehicle(vehicle_type)
    zone_distance_slabs.active.for_vehicle(vehicle_type).ordered
  end
  
  # Check if zone has custom slabs for a vehicle
  def has_custom_slabs?(vehicle_type)
    zone_distance_slabs.active.for_vehicle(vehicle_type).exists?
  end
end
