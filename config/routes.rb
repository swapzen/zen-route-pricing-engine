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

      # Approval workflow
      post 'submit_for_approval', to: 'configs#submit_for_approval'
      post 'approve_config', to: 'configs#approve_config'
      post 'reject_config', to: 'configs#reject_config'

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

      # Surge buckets (per-hex H3 surge pricing)
      get 'surge_buckets', to: 'surge_buckets#index'
      post 'surge_buckets', to: 'surge_buckets#create'
      post 'surge_buckets/bulk_update', to: 'surge_buckets#bulk_update'
      get 'surge_buckets/heatmap', to: 'surge_buckets#heatmap'
      delete 'surge_buckets/clear', to: 'surge_buckets#clear'

      # Drift analysis (P0)
      get 'drift_report', to: 'drift#drift_report'
      get 'drift_summary', to: 'drift#drift_summary'

      # Backtesting (P0)
      post 'backtests', to: 'backtests#create'
      get 'backtests', to: 'backtests#index'
      get 'backtests/:id', to: 'backtests#show'

      # Control plane (P1)
      get 'change_logs', to: 'control_plane#change_logs'
      get 'rollout_flags', to: 'control_plane#list_rollout_flags'
      post 'rollout_flags', to: 'control_plane#set_rollout_flag'
      post 'emergency_freeze', to: 'control_plane#emergency_freeze'
      delete 'emergency_freeze', to: 'control_plane#unfreeze'
      get 'freeze_status', to: 'control_plane#freeze_status'

      # Market state (P1)
      get 'market/dashboard', to: 'market_state#dashboard'
      get 'market/zone_health', to: 'market_state#zone_health'
      get 'market/pressure_map', to: 'market_state#pressure_map'

      # Merchant policies (P1)
      get 'merchant_policies', to: 'merchant_policies#index'
      post 'merchant_policies', to: 'merchant_policies#create'
      patch 'merchant_policies/:id', to: 'merchant_policies#update'
      delete 'merchant_policies/:id', to: 'merchant_policies#destroy'
      post 'merchant_policies/simulate', to: 'merchant_policies#simulate'

      # Model optimization (P2)
      get 'models/scores', to: 'models#scores'
      get 'models/accuracy', to: 'models#accuracy'
      post 'models/configure', to: 'models#configure'
      get 'models/comparison', to: 'models#comparison'

      # Competitor rate cards
      get 'competitor_rates', to: 'competitor_rates#index'
      get 'competitor_comparison', to: 'competitor_rates#comparison'

      # Route pricing matrix (verification)
      get 'route_matrix', to: 'route_matrix#index'
      get 'route_matrix/landmark_routes', to: 'route_matrix#landmark_routes'
      get 'route_matrix/calibration_routes', to: 'route_matrix#calibration_routes'
      post 'route_matrix/generate_quote', to: 'route_matrix#generate_quote'

      # Porter benchmarks
      get 'porter_benchmarks', to: 'porter_benchmarks#index'
      post 'porter_benchmarks/bulk_save', to: 'porter_benchmarks#bulk_save'
      post 'porter_benchmarks/recalibrate', to: 'porter_benchmarks#recalibrate'

      # Provider health (circuit breaker status)
      get 'provider_health', to: 'provider_health#show'

      # Zone toggle
      patch 'zones/:id/toggle', to: 'zones#toggle'

      # Zone map (boundaries + corridors)
      get 'zone_map/zones', to: 'zone_map#zones'
      get 'zone_map/corridors', to: 'zone_map#corridors'
      get 'zone_map/zone_pricing_summary', to: 'zone_map#zone_pricing_summary'
      get 'zone_map/corridor_pricing', to: 'zone_map#corridor_pricing'
      post 'zone_map/compute_boundaries', to: 'zone_map#compute_boundaries'
      post 'zone_map/detect_corridors', to: 'zone_map#detect_corridors'
    end
  end
end
