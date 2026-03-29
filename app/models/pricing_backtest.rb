# frozen_string_literal: true

class PricingBacktest < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  validates :city_code, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :recent, ->(n = 10) { order(created_at: :desc).limit(n) }

  def start!
    update!(status: 'running', started_at: Time.current)
  end

  def complete!(result_data)
    update!(
      status: 'completed',
      results: result_data,
      completed_at: Time.current
    )
  end

  def fail!(error_message)
    update!(
      status: 'failed',
      results: (results || {}).merge('error' => error_message),
      completed_at: Time.current
    )
  end
end
