# frozen_string_literal: true

class ZoneH3Mapping < ApplicationRecord
  belongs_to :zone

  validates :city_code, presence: true
  validates :h3_index_r7, presence: true, unless: -> { h3_index_r8.present? }
  # R8 cells are the unique key when present (non-overlapping source of truth)
  validates :h3_index_r8, uniqueness: { scope: :zone_id }, allow_nil: true

  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :for_r7, ->(h3_index) { where(h3_index_r7: h3_index) }
  scope :for_r8, ->(h3_index) { where(h3_index_r8: h3_index) }
  scope :for_r9, ->(h3_index) { where(h3_index_r9: h3_index) }
  scope :boundary_cells, -> { where(is_boundary: true) }
  scope :serviceable, -> { where(serviceable: true) }

  # Find all zone mappings for a given R7 hex in a city
  def self.find_zones_for_r7(h3_index, city_code)
    for_city(city_code).for_r7(h3_index).includes(:zone)
  end

  # Find all zone mappings for a given R8 hex in a city
  def self.find_zones_for_r8(h3_index, city_code)
    for_city(city_code).for_r8(h3_index).includes(:zone)
  end

  # Find single zone mapping for a given R9 hex (boundary disambiguation)
  def self.find_zone_for_r9(h3_index, city_code)
    for_city(city_code).for_r9(h3_index).includes(:zone).first
  end
end
