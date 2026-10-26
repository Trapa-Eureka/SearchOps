module Api
  module V1
    class MetricsController < BaseController
      # GET /api/v1/metrics/summary?window=24h  (1h, 24h, 7d, or 30d)
      def summary
        window = params.fetch(:window, MetricsSummary::DEFAULT_WINDOW).to_s
        unless MetricsSummary::WINDOWS.key?(window)
          return render_error(:bad_request, "bad_request", "Unknown window", { allowed: MetricsSummary::WINDOWS.keys })
        end

        render json: { data: MetricsSummary.call(window: window) }
      end
    end
  end
end
