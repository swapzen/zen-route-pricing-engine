class ApplicationController < ActionController::API
  before_action :set_request_context
  before_action :authenticate_api_key!
  before_action :check_rate_limit!

  RATE_LIMIT_WINDOW = 60  # seconds
  RATE_LIMIT_MAX = 1000   # requests per window per API key

  private

  def set_request_context
    Thread.current[:request_id] = request.request_id || SecureRandom.uuid
    Thread.current[:client_ip] = request.remote_ip
  end

  def authenticate_api_key!
    expected_key = ENV['SERVICE_API_KEY'].to_s

    if expected_key.blank?
      render json: { error: 'Unauthorized: SERVICE_API_KEY is not configured' }, status: :unauthorized
      return
    end

    api_key = request.headers['X-API-KEY']

    unless api_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, expected_key)
      render json: { error: 'Unauthorized: Invalid or missing API key' }, status: :unauthorized
    end
  end

  def check_rate_limit!
    return if Rails.env.test?

    key = "rate_limit:#{request.headers['X-API-KEY'].to_s[0..8]}:#{(Time.current.to_i / RATE_LIMIT_WINDOW)}"
    count = Rails.cache.increment(key, 1, expires_in: RATE_LIMIT_WINDOW.seconds)

    if count && count > RATE_LIMIT_MAX
      render json: { error: "Rate limit exceeded. Max #{RATE_LIMIT_MAX} requests per minute." }, status: :too_many_requests
    end
  end
end
