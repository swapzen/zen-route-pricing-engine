class AddPorterVehicleMetadata < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_configs, :vendor_vehicle_code, :string
    add_column :pricing_configs, :weight_capacity_kg, :integer
    add_column :pricing_configs, :display_name, :string
    add_column :pricing_configs, :description, :text
    
    add_index :pricing_configs, [:vendor_vehicle_code, :city_code], name: 'index_pricing_configs_on_vendor_code_and_city'
  end
end
