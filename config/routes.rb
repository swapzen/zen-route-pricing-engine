Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Route Pricing Domain
  namespace :route_pricing do
    # Public endpoints (Internal to SwapZen network)
    post 'create_quote', to: 'quotes#create'
    post 'multi_quote', to: 'quotes#multi_quote'
    post 'round_trip_quote', to: 'quotes#round_trip_quote'
    post 'validate_quote', to: 'quotes#validate_quote'
    post 'record_actual', to: 'quotes#record_actual'

    # Admin endpoints
    namespace :admin do
      patch 'update_config', to: 'configs#update'
      post 'create_surge_rule', to: 'surge_rules#create'
      get 'list_configs', to: 'configs#index'
      patch 'deactivate_surge_rule', to: 'surge_rules#deactivate'

      # Vendor rate card management
      post 'sync_vendor_rates', to: 'vendor_rates#sync'
      get 'vendor_rate_cards', to: 'vendor_rates#index'
      get 'margin_report', to: 'vendor_rates#margin_report'

      # Auto-zone generation
      post 'auto_zones/preview', to: 'auto_zones#preview'
      post 'auto_zones/generate', to: 'auto_zones#generate'
      get 'auto_zones/stats', to: 'auto_zones#stats'
      get 'auto_zones/cells', to: 'auto_zones#cells'
      delete 'auto_zones/remove', to: 'auto_zones#remove'
      patch 'auto_zones/toggle_cell', to: 'auto_zones#toggle_cell'
    end
  end
end
