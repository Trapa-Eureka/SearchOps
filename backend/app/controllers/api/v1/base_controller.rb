module Api
  module V1
    # Shared JSON error contract:
    #   { "error": { "code": "...", "message": "...", "details": { field: [messages] } } }
    # Internal exception messages are never returned to the client.
    class BaseController < ApplicationController
      include Paginatable

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordNotUnique, with: :render_conflict
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request

      private

      def render_error(status, code, message, details = nil)
        body = { code: code, message: message }
        body[:details] = details if details
        render json: { error: body }, status: status
      end

      def render_validation_errors(record)
        render_error(:unprocessable_content, "validation_failed", "Validation failed", record.errors.messages)
      end

      def render_not_found(_error)
        render_error(:not_found, "not_found", "Resource not found")
      end

      def render_conflict(_error)
        render_error(:conflict, "conflict", "A record with the same unique values already exists")
      end

      def render_bad_request(_error)
        render_error(:bad_request, "bad_request", "Missing or malformed request body")
      end
    end
  end
end
