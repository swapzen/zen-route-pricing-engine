class AddH3ContextToPricingQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_quotes, :pickup_h3_r8, :string
    add_column :pricing_quotes, :drop_h3_r8, :string
    add_column :pricing_quotes, :pickup_h3_r7, :string
    add_column :pricing_quotes, :drop_h3_r7, :string
    add_column :pricing_quotes, :h3_surge_multiplier, :float, default: 1.0

    add_index :pricing_quotes, [:city_code, :pickup_h3_r8], name: 'idx_quotes_pickup_h3'
    add_index :pricing_quotes, [:city_code, :drop_h3_r8], name: 'idx_quotes_drop_h3'
  end
end
