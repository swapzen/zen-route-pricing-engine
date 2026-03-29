# frozen_string_literal: true

class AddApprovalWorkflowToPricingConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_configs, :approval_status, :string, default: 'approved'
    add_column :pricing_configs, :submitted_by, :string
    add_column :pricing_configs, :reviewed_by, :string
    add_column :pricing_configs, :reviewed_at, :datetime
    add_column :pricing_configs, :rejection_reason, :string
    add_column :pricing_configs, :change_summary, :text
    add_index :pricing_configs, :approval_status
  end
end
