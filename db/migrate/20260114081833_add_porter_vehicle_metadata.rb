class AddPorterVehicleMetadata < ActiveRecord::Migration[8.0]
  def up
    add_column :pricing_configs, :vendor_vehicle_code, :string unless column_exists?(:pricing_configs, :vendor_vehicle_code)
    add_column :pricing_configs, :weight_capacity_kg, :integer unless column_exists?(:pricing_configs, :weight_capacity_kg)
    add_column :pricing_configs, :display_name, :string unless column_exists?(:pricing_configs, :display_name)
    add_column :pricing_configs, :description, :text unless column_exists?(:pricing_configs, :description)

    add_index :pricing_configs, [:vendor_vehicle_code, :city_code], name: "index_pricing_configs_on_vendor_code_and_city", if_not_exists: true
  end

  def down
    remove_index :pricing_configs, name: "index_pricing_configs_on_vendor_code_and_city", if_exists: true
    remove_column :pricing_configs, :description if column_exists?(:pricing_configs, :description)
    remove_column :pricing_configs, :display_name if column_exists?(:pricing_configs, :display_name)
    remove_column :pricing_configs, :weight_capacity_kg if column_exists?(:pricing_configs, :weight_capacity_kg)
    remove_column :pricing_configs, :vendor_vehicle_code if column_exists?(:pricing_configs, :vendor_vehicle_code)
  end
end
