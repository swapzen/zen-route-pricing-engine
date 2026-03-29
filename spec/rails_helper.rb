# frozen_string_literal: true

require 'spec_helper'
# Use development env — shared CockroachDB across all SwapZen services
ENV['RAILS_ENV'] ||= 'development'
ENV['PRICING_MODE'] ||= 'calibration'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'

# Load all support files
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Skip maintain_test_schema! — shared CockroachDB across dev/test envs
# Migrations are managed via swapzen-api and this engine's own migrations


RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join('spec/fixtures')]
  # Use transactional fixtures — each test runs in a transaction that rolls back
  # This works well with CockroachDB and avoids FK constraint issues
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
