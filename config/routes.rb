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
    end
  end
end
