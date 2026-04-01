# frozen_string_literal: true

module RoutePricing
  module Services
    # Recalibration Optimizer v3 — Analytical solve with tolerance-aware grid search
    #
    # Uses least-squares regression + binary search + 2D grid search with
    # lexicographic scoring (minimize failures first, then max error).
    #
    # Input:  Array of benchmark routes with zone/vehicle/time/price/distance data
    # Output: Recommendations with projected pass rate
    class RecalibrationOptimizer
      BASE_DISTANCE_M = 1000
      TOLERANCE_LOW = -3.0   # Minimum acceptable % deviation
      TOLERANCE_HIGH = 16.0  # Maximum acceptable % deviation

      BenchmarkRoute = Struct.new(
        :origin_zone_id, :dest_zone_id, :vehicle_type, :time_band,
        :benchmark_price_paise, :distance_m, :duration_min,
        keyword_init: true
      )

      Recommendation = Struct.new(
        :pricing_type, :zone_id, :from_zone_id, :to_zone_id,
        :vehicle_type, :time_band, :field, :old_value, :new_value,
        :impact_routes, :confidence,
        keyword_init: true
      )

      def initialize(city_code: 'hyd', time_bands: nil, vehicle_types: nil)
        @city_code = city_code
        @time_bands = time_bands || %w[
          early_morning morning_rush midday afternoon
          evening_rush night weekend_day weekend_night
        ]
        @vehicle_types = vehicle_types || VehicleCategories::ALL_VEHICLES
      end

      # Main entry point: optimize pricing based on benchmark data
      #
      # @param benchmarks [Array<Hash>] each with keys:
      #   origin_zone_id, dest_zone_id, vehicle_type, time_band,
      #   benchmark_price_paise, distance_m, duration_min
      # @param dry_run [Boolean] if true, don't apply changes to DB
      # @return [Hash] { recommendations:, pass_rate:, failures:, summary: }
      def optimize(benchmarks, dry_run: true)
        routes = benchmarks.map { |b| BenchmarkRoute.new(**b.slice(*BenchmarkRoute.members)) }
        return empty_result('No benchmark routes provided') if routes.empty?

        # Group routes by pricing entity
        groups = group_by_pricing_entity(routes)

        recommendations = []
        all_results = []

        groups.each do |key, points|
          group_recs, group_results = solve_group(key, points)
          recommendations.concat(group_recs)
          all_results.concat(group_results)
        end

        # Calculate pass rate
        total = all_results.size
        passed = all_results.count { |r| r[:passed] }
        pass_rate = total > 0 ? (passed.to_f / total * 100).round(1) : 0.0

        failures = all_results.reject { |r| r[:passed] }.map do |r|
          {
            vehicle_type: r[:vehicle_type],
            time_band: r[:time_band],
            benchmark_paise: r[:benchmark_paise],
            projected_paise: r[:projected_paise],
            deviation_pct: r[:deviation_pct],
            origin_zone_id: r[:origin_zone_id],
            dest_zone_id: r[:dest_zone_id]
          }
        end

        {
          recommendations: recommendations.map(&method(:recommendation_to_hash)),
          pass_rate: pass_rate,
          total_routes: total,
          passed: passed,
          failed: failures.size,
          failures: failures,
          summary: build_summary(recommendations, pass_rate, total)
        }
      end

      # Simulate: given proposed changes, project pass rate without applying
      #
      # @param benchmarks [Array<Hash>] benchmark routes
      # @param changes [Array<Hash>] proposed pricing changes
      # @return [Hash] { projected_pass_rate:, per_route_results:, delta: }
      def simulate(benchmarks, changes)
        routes = benchmarks.map { |b| BenchmarkRoute.new(**b.slice(*BenchmarkRoute.members)) }
        return empty_result('No benchmark routes provided') if routes.empty?

        # Build a pricing overlay from proposed changes
        overlay = build_overlay(changes)

        results = routes.map do |route|
          projected = project_price_with_overlay(route, overlay)
          deviation = route.benchmark_price_paise > 0 ?
            ((projected - route.benchmark_price_paise).to_f / route.benchmark_price_paise * 100).round(1) : 0.0
          passed = deviation >= TOLERANCE_LOW && deviation <= TOLERANCE_HIGH

          {
            origin_zone_id: route.origin_zone_id,
            dest_zone_id: route.dest_zone_id,
            vehicle_type: route.vehicle_type,
            time_band: route.time_band,
            benchmark_paise: route.benchmark_price_paise,
            projected_paise: projected,
            deviation_pct: deviation,
            passed: passed
          }
        end

        # Also compute current pass rate (without changes)
        current_results = routes.map do |route|
          current = project_current_price(route)
          deviation = route.benchmark_price_paise > 0 ?
            ((current - route.benchmark_price_paise).to_f / route.benchmark_price_paise * 100).round(1) : 0.0
          { passed: deviation >= TOLERANCE_LOW && deviation <= TOLERANCE_HIGH }
        end

        current_pass_rate = (current_results.count { |r| r[:passed] }.to_f / current_results.size * 100).round(1)
        projected_pass_rate = (results.count { |r| r[:passed] }.to_f / results.size * 100).round(1)

        {
          current_pass_rate: current_pass_rate,
          projected_pass_rate: projected_pass_rate,
          delta: (projected_pass_rate - current_pass_rate).round(1),
          total_routes: results.size,
          improved: results.count { |r| r[:passed] } - current_results.count { |r| r[:passed] },
          per_route_results: results
        }
      end

      private

      def empty_result(message)
        { recommendations: [], pass_rate: 0.0, total_routes: 0, passed: 0,
          failed: 0, failures: [], summary: message }
      end

      # Group benchmark routes by their pricing entity (intra-zone or corridor)
      def group_by_pricing_entity(routes)
        groups = {}
        routes.each do |route|
          if route.origin_zone_id == route.dest_zone_id
            key = [:intra, route.origin_zone_id, route.vehicle_type, route.time_band]
          else
            key = [:corridor, route.origin_zone_id, route.dest_zone_id, route.vehicle_type, route.time_band]
          end
          (groups[key] ||= []) << route
        end
        groups
      end

      # Solve a single pricing group using least-squares + grid search
      def solve_group(key, points)
        data_points = points.map do |route|
          target_raw = find_target_raw_subtotal(route.benchmark_price_paise)
          chargeable_km = [0, (route.distance_m - BASE_DISTANCE_M) / 1000.0].max
          bm = band_multiplier_for(route.vehicle_type, route.distance_m)
          effective_x = chargeable_km * bm

          { route: route, target_raw: target_raw, effective_x: effective_x }
        end

        # Least-squares regression: target_raw = base + rate * effective_x
        base_fare, per_km_rate = least_squares_solve(data_points)

        # Grid search with tolerance-aware lexicographic scoring
        base_fare, per_km_rate = grid_search(base_fare, per_km_rate, data_points)

        # Build recommendations and per-route results
        build_group_output(key, base_fare, per_km_rate, data_points)
      end

      def least_squares_solve(data_points)
        n = data_points.size

        if n == 1
          pt = data_points.first
          if pt[:effective_x] <= 0.001
            return [pt[:target_raw], 0]
          else
            base = (pt[:target_raw] * 0.6).round
            rate = ((pt[:target_raw] - base) / pt[:effective_x]).round
            return [base, rate]
          end
        end

        sum_x = data_points.sum { |p| p[:effective_x] }
        sum_y = data_points.sum { |p| p[:target_raw].to_f }
        sum_xy = data_points.sum { |p| p[:effective_x] * p[:target_raw].to_f }
        sum_x2 = data_points.sum { |p| p[:effective_x]**2 }
        mean_x = sum_x / n
        mean_y = sum_y / n
        denom = sum_x2 - n * mean_x**2

        if denom.abs < 0.001
          return [mean_y.round, 0]
        end

        rate = ((sum_xy - n * mean_x * mean_y) / denom).round
        base = (mean_y - rate * mean_x).round
        [[base, 0].max, [rate, 0].max]
      end

      def grid_search(base_fare, per_km_rate, data_points)
        # Coarse search
        best_base, best_rate, best_fails, best_max_err = search_grid(
          base_fare, per_km_rate, data_points,
          range: 2000, step: 100
        )

        # Fine-grained search around best
        fine_base, fine_rate, _, _ = search_grid(
          best_base, best_rate, data_points,
          range: 50, step: 5
        )

        [fine_base, fine_rate]
      end

      def search_grid(center_base, center_rate, data_points, range:, step:)
        best_base = center_base
        best_rate = center_rate
        best_fails = data_points.size + 1
        best_max_err = Float::INFINITY

        (-range..range).step(step).each do |db|
          (-range..range).step(step).each do |dr|
            test_base = center_base + db
            test_rate = center_rate + dr
            next if test_base < 0 || test_rate < 0

            fails = 0
            max_err = 0
            data_points.each do |pt|
              final = simulate_full_price(test_base, test_rate, pt[:effective_x])
              signed_pct = (final - pt[:route].benchmark_price_paise).to_f / pt[:route].benchmark_price_paise * 100
              fails += 1 unless signed_pct >= TOLERANCE_LOW && signed_pct <= TOLERANCE_HIGH
              max_err = [max_err, signed_pct.abs].max
            end

            if fails < best_fails || (fails == best_fails && max_err < best_max_err)
              best_fails = fails
              best_max_err = max_err
              best_base = test_base
              best_rate = test_rate
            end
          end
        end

        [best_base, best_rate, best_fails, best_max_err]
      end

      # Simulate the full price pipeline: raw → guardrail → final
      def simulate_full_price(base_fare, per_km_rate, effective_x)
        predicted_raw = base_fare + (per_km_rate * effective_x).round
        simulate_guardrail(predicted_raw)
      end

      def simulate_guardrail(raw)
        final_price = raw.round
        pg_fee = (final_price * 0.02).round
        total_cost = raw + pg_fee + 200 + 10
        margin_pct = total_cost > 0 ? ((final_price - total_cost).to_f / total_cost * 100) : 0.0
        if margin_pct < 5.0
          required = (total_cost * 1.05).ceil
          ((required / 1000.0).ceil * 1000).to_i
        else
          final_price
        end
      end

      def best_guardrail_target(porter_paise)
        lo_mult = ((porter_paise * 0.97) / 1000.0).floor * 1000
        hi_mult = ((porter_paise * 1.16) / 1000.0).ceil * 1000

        best = nil
        best_diff = Float::INFINITY
        (lo_mult..hi_mult).step(1000).each do |candidate|
          pct = (candidate - porter_paise).to_f / porter_paise * 100
          next unless pct >= TOLERANCE_LOW && pct <= TOLERANCE_HIGH
          diff = pct.abs
          if diff < best_diff
            best_diff = diff
            best = candidate
          end
        end
        best || porter_paise
      end

      def find_raw_for_guardrail_target(guardrail_target)
        lo = 0.0
        hi = guardrail_target * 2.0

        100.times do
          mid = (lo + hi) / 2.0
          price = simulate_guardrail(mid.round)
          if price < guardrail_target
            lo = mid
          elsif price > guardrail_target
            hi = mid
          else
            return mid.round
          end
        end
        ((guardrail_target / 1.05 - 210) / 1.02 * 0.99).round
      end

      def find_target_raw_subtotal(porter_paise)
        target = best_guardrail_target(porter_paise)
        find_raw_for_guardrail_target(target)
      end

      def band_multiplier_for(vehicle_type, distance_m)
        distance_km = distance_m / 1000.0
        band = case distance_km
               when 0...5   then :micro
               when 5...12  then :short
               when 12...20 then :medium
               else              :long
               end
        category = VehicleCategories.category_for(vehicle_type)
        multipliers = case category
                      when :small then { micro: 0.85, short: 1.00, medium: 1.05, long: 1.00 }
                      when :mid   then { micro: 0.90, short: 1.00, medium: 1.05, long: 1.00 }
                      when :heavy then { micro: 0.95, short: 1.00, medium: 1.05, long: 1.00 }
                      end
        multipliers[band] || 1.0
      end

      # Build recommendations and results for a solved group
      def build_group_output(key, base_fare, per_km_rate, data_points)
        recommendations = []
        results = []

        if key[0] == :intra
          _, zone_id, vehicle_type, time_band = key
          zvp = ZoneVehiclePricing.find_by(
            city_code: @city_code, zone_id: zone_id,
            vehicle_type: vehicle_type, active: true
          )

          if zvp
            zvtp = zvp.time_pricings.where(active: true).find_by(time_band: time_band)
            target = zvtp || zvp

            if target.base_fare_paise != base_fare
              recommendations << Recommendation.new(
                pricing_type: zvtp ? 'ZoneVehicleTimePricing' : 'ZoneVehiclePricing',
                zone_id: zone_id,
                vehicle_type: vehicle_type,
                time_band: time_band,
                field: 'base_fare_paise',
                old_value: target.base_fare_paise,
                new_value: base_fare,
                impact_routes: data_points.size,
                confidence: compute_confidence(data_points, base_fare, per_km_rate)
              )
            end

            if target.per_km_rate_paise != per_km_rate
              recommendations << Recommendation.new(
                pricing_type: zvtp ? 'ZoneVehicleTimePricing' : 'ZoneVehiclePricing',
                zone_id: zone_id,
                vehicle_type: vehicle_type,
                time_band: time_band,
                field: 'per_km_rate_paise',
                old_value: target.per_km_rate_paise,
                new_value: per_km_rate,
                impact_routes: data_points.size,
                confidence: compute_confidence(data_points, base_fare, per_km_rate)
              )
            end
          end
        elsif key[0] == :corridor
          _, from_zone_id, to_zone_id, vehicle_type, time_band = key
          zpvp = ZonePairVehiclePricing.where('LOWER(city_code) = LOWER(?)', @city_code)
            .find_by(
              from_zone_id: from_zone_id, to_zone_id: to_zone_id,
              vehicle_type: vehicle_type, time_band: time_band, active: true
            )

          if zpvp
            if zpvp.base_fare_paise != base_fare
              recommendations << Recommendation.new(
                pricing_type: 'ZonePairVehiclePricing',
                from_zone_id: from_zone_id,
                to_zone_id: to_zone_id,
                vehicle_type: vehicle_type,
                time_band: time_band,
                field: 'base_fare_paise',
                old_value: zpvp.base_fare_paise,
                new_value: base_fare,
                impact_routes: data_points.size,
                confidence: compute_confidence(data_points, base_fare, per_km_rate)
              )
            end

            if zpvp.per_km_rate_paise != per_km_rate
              recommendations << Recommendation.new(
                pricing_type: 'ZonePairVehiclePricing',
                from_zone_id: from_zone_id,
                to_zone_id: to_zone_id,
                vehicle_type: vehicle_type,
                time_band: time_band,
                field: 'per_km_rate_paise',
                old_value: zpvp.per_km_rate_paise,
                new_value: per_km_rate,
                impact_routes: data_points.size,
                confidence: compute_confidence(data_points, base_fare, per_km_rate)
              )
            end
          end
        end

        # Project results for each data point
        data_points.each do |pt|
          final = simulate_full_price(base_fare, per_km_rate, pt[:effective_x])
          deviation = pt[:route].benchmark_price_paise > 0 ?
            ((final - pt[:route].benchmark_price_paise).to_f / pt[:route].benchmark_price_paise * 100).round(1) : 0.0
          passed = deviation >= TOLERANCE_LOW && deviation <= TOLERANCE_HIGH

          results << {
            origin_zone_id: pt[:route].origin_zone_id,
            dest_zone_id: pt[:route].dest_zone_id,
            vehicle_type: pt[:route].vehicle_type,
            time_band: pt[:route].time_band,
            benchmark_paise: pt[:route].benchmark_price_paise,
            projected_paise: final,
            deviation_pct: deviation,
            passed: passed
          }
        end

        [recommendations, results]
      end

      def compute_confidence(data_points, base_fare, per_km_rate)
        return 0.0 if data_points.empty?

        passed = data_points.count do |pt|
          final = simulate_full_price(base_fare, per_km_rate, pt[:effective_x])
          deviation = (final - pt[:route].benchmark_price_paise).to_f / pt[:route].benchmark_price_paise * 100
          deviation >= TOLERANCE_LOW && deviation <= TOLERANCE_HIGH
        end

        (passed.to_f / data_points.size * 100).round(1)
      end

      def recommendation_to_hash(rec)
        {
          pricing_type: rec.pricing_type,
          zone_id: rec.zone_id,
          from_zone_id: rec.from_zone_id,
          to_zone_id: rec.to_zone_id,
          vehicle_type: rec.vehicle_type,
          time_band: rec.time_band,
          field: rec.field,
          old_value: rec.old_value,
          new_value: rec.new_value,
          impact_routes: rec.impact_routes,
          confidence: rec.confidence
        }.compact
      end

      def build_summary(recommendations, pass_rate, total)
        changes_by_type = recommendations.group_by(&:pricing_type).transform_values(&:size)
        "#{recommendations.size} changes across #{changes_by_type.size} pricing types. " \
          "Projected pass rate: #{pass_rate}% (#{total} routes)"
      end

      # Build pricing overlay from proposed changes for simulation
      def build_overlay(changes)
        overlay = {}
        changes.each do |change|
          key = [change[:pricing_type], change[:zone_id], change[:from_zone_id],
                 change[:to_zone_id], change[:vehicle_type], change[:time_band]].compact
          overlay[key] ||= {}
          overlay[key][change[:field].to_s] = change[:new_value].to_i
        end
        overlay
      end

      # Project price for a route using current DB pricing + overlay changes
      def project_price_with_overlay(route, overlay)
        base_fare, per_km_rate = current_pricing_for(route)

        # Apply overlay if matching
        overlay.each do |key, fields|
          if matches_route?(key, route)
            base_fare = fields['base_fare_paise'] if fields['base_fare_paise']
            per_km_rate = fields['per_km_rate_paise'] if fields['per_km_rate_paise']
          end
        end

        chargeable_km = [0, (route.distance_m - BASE_DISTANCE_M) / 1000.0].max
        bm = band_multiplier_for(route.vehicle_type, route.distance_m)
        effective_x = chargeable_km * bm
        simulate_full_price(base_fare, per_km_rate, effective_x)
      end

      def project_current_price(route)
        base_fare, per_km_rate = current_pricing_for(route)
        chargeable_km = [0, (route.distance_m - BASE_DISTANCE_M) / 1000.0].max
        bm = band_multiplier_for(route.vehicle_type, route.distance_m)
        effective_x = chargeable_km * bm
        simulate_full_price(base_fare, per_km_rate, effective_x)
      end

      def current_pricing_for(route)
        same_zone = route.origin_zone_id == route.dest_zone_id

        if same_zone
          zvp = ZoneVehiclePricing.find_by(
            city_code: @city_code, zone_id: route.origin_zone_id,
            vehicle_type: route.vehicle_type, active: true
          )
          if zvp
            zvtp = zvp.time_pricings.where(active: true).find_by(time_band: route.time_band)
            target = zvtp || zvp
            return [target.base_fare_paise, target.per_km_rate_paise]
          end
        else
          zpvp = ZonePairVehiclePricing.where('LOWER(city_code) = LOWER(?)', @city_code)
            .find_by(
              from_zone_id: route.origin_zone_id, to_zone_id: route.dest_zone_id,
              vehicle_type: route.vehicle_type, time_band: route.time_band, active: true
            )
          return [zpvp.base_fare_paise, zpvp.per_km_rate_paise] if zpvp
        end

        # Fallback to city default
        config = PricingConfig.where(city_code: @city_code, vehicle_type: route.vehicle_type, active: true)
                              .order(version: :desc).first
        config ? [config.base_fare_paise, config.per_km_rate_paise] : [0, 0]
      end

      def matches_route?(key, route)
        pricing_type = key[0]
        same_zone = route.origin_zone_id == route.dest_zone_id

        case pricing_type
        when 'ZoneVehiclePricing', 'ZoneVehicleTimePricing'
          same_zone && key.include?(route.origin_zone_id) &&
            key.include?(route.vehicle_type) && key.include?(route.time_band)
        when 'ZonePairVehiclePricing'
          !same_zone && key.include?(route.origin_zone_id) &&
            key.include?(route.dest_zone_id) && key.include?(route.vehicle_type) &&
            key.include?(route.time_band)
        else
          false
        end
      end
    end
  end
end
