# frozen_string_literal: true

class AddRouteSegmentPricing < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_quotes, :route_segments_json, :jsonb, default: nil
  end
end
