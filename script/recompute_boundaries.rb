require_relative '../config/environment'
result = RoutePricing::Services::ZoneBoundaryComputer.compute_for_city!('hyd')
puts "Boundaries recomputed: #{result.inspect}"
