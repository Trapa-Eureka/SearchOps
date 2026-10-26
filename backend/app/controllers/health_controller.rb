class HealthController < ApplicationController
  def show
    if database_up?
      render json: { status: "ok", database: "up" }
    else
      render json: { status: "degraded", database: "down" }, status: :service_unavailable
    end
  end

  private

  def database_up?
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") == 1 }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.error("health check database failure: #{error.class}")
    false
  end
end
