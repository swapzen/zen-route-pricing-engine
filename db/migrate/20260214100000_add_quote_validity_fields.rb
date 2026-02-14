# frozen_string_literal: true

class AddQuoteValidityFields < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_quotes, :valid_until, :datetime
    add_index :pricing_quotes, :valid_until

    add_column :pricing_configs, :quote_validity_minutes, :integer, default: 10
  end
end
