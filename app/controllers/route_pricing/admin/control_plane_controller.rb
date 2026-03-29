# frozen_string_literal: true

module RoutePricing
  module Admin
    class ControlPlaneController < ApplicationController
      # GET /route_pricing/admin/change_logs
      def change_logs
        logs = PricingChangeLog.all
        logs = logs.for_city(params[:city_code]) if params[:city_code].present?
        logs = logs.where(entity_type: params[:entity_type]) if params[:entity_type].present?
        logs = logs.by_actor(params[:actor]) if params[:actor].present?
        logs = logs.order(created_at: :desc)
                   .limit((params[:limit] || 50).to_i)
                   .offset((params[:offset] || 0).to_i)

        render json: {
          change_logs: logs.map do |log|
            {
              id: log.id,
              entity_type: log.entity_type,
              entity_id: log.entity_id,
              action: log.action,
              actor: log.actor,
              diff: log.diff,
              city_code: log.city_code,
              created_at: log.created_at.iso8601
            }
          end
        }, status: :ok
      end

      # GET /route_pricing/admin/rollout_flags
      def list_rollout_flags
        flags = PricingRolloutFlag.all
        flags = flags.for_city(params[:city_code]) if params[:city_code].present?
        flags = flags.for_flag(params[:flag_name]) if params[:flag_name].present?

        render json: {
          flags: flags.map do |flag|
            {
              id: flag.id,
              flag_name: flag.flag_name,
              city_code: flag.city_code,
              enabled: flag.enabled,
              rollout_pct: flag.rollout_pct,
              metadata: flag.metadata,
              updated_at: flag.updated_at.iso8601
            }
          end
        }, status: :ok
      end

      # POST /route_pricing/admin/rollout_flags
      def set_rollout_flag
        flag = PricingRolloutFlag.set!(
          params[:flag_name],
          enabled: params[:enabled] != false && params[:enabled] != 'false',
          city_code: params[:city_code],
          rollout_pct: (params[:rollout_pct] || 100).to_i
        )

        PricingChangeLog.log!(flag, 'update', params[:actor] || 'admin',
                              after: { enabled: flag.enabled, rollout_pct: flag.rollout_pct })

        render json: {
          success: true,
          flag: {
            id: flag.id,
            flag_name: flag.flag_name,
            city_code: flag.city_code,
            enabled: flag.enabled,
            rollout_pct: flag.rollout_pct
          }
        }, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /route_pricing/admin/emergency_freeze
      def emergency_freeze
        freeze = PricingEmergencyFreeze.create!(
          city_code: params[:city_code],
          reason: params[:reason],
          activated_by: params[:actor] || 'admin',
          activated_at: Time.current
        )

        PricingChangeLog.log!(freeze, 'activate', params[:actor] || 'admin',
                              after: { city_code: freeze.city_code, reason: freeze.reason })

        render json: {
          success: true,
          freeze_id: freeze.id,
          city_code: freeze.city_code,
          reason: freeze.reason,
          activated_at: freeze.activated_at.iso8601
        }, status: :created
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # DELETE /route_pricing/admin/emergency_freeze
      def unfreeze
        freezes = PricingEmergencyFreeze.where(active: true)
        freezes = freezes.where(city_code: params[:city_code]) if params[:city_code].present?
        freezes = freezes.where(city_code: nil) unless params[:city_code].present?

        if freezes.empty?
          return render json: { error: 'No active freeze found' }, status: :not_found
        end

        actor = params[:actor] || 'admin'
        freezes.each { |f| f.deactivate!(actor) }

        render json: { success: true, deactivated_count: freezes.size }, status: :ok
      end

      # GET /route_pricing/admin/freeze_status
      def freeze_status
        global_freezes = PricingEmergencyFreeze.global_active
        city_freezes = params[:city_code].present? ?
                         PricingEmergencyFreeze.active_for_city(params[:city_code]) : []

        render json: {
          globally_frozen: global_freezes.exists?,
          city_frozen: city_freezes.is_a?(ActiveRecord::Relation) ? city_freezes.exists? : city_freezes.any?,
          global_freezes: global_freezes.map { |f| format_freeze(f) },
          city_freezes: (city_freezes.is_a?(ActiveRecord::Relation) ? city_freezes : []).map { |f| format_freeze(f) }
        }, status: :ok
      end

      private

      def format_freeze(freeze)
        {
          id: freeze.id,
          city_code: freeze.city_code,
          reason: freeze.reason,
          activated_by: freeze.activated_by,
          activated_at: freeze.activated_at.iso8601
        }
      end
    end
  end
end
