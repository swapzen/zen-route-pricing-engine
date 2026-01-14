class ApplicationController < ActionController::API
  before_action :authenticate_api_key!

  private

  def authenticate_api_key!
    # Skip auth in development if no key is set (for easy local testing)
    return if Rails.env.development? && ENV['SERVICE_API_KEY'].blank?

    api_key = request.headers['X-API-KEY'] || params[:api_key]
    
    unless api_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, ENV['SERVICE_API_KEY'].to_s)
      render json: { error: 'Unauthorized: Invalid or missing API key' }, status: :unauthorized
    end
  end
end
