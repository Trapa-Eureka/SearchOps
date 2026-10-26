module Intent
  class ClassifierError < StandardError
    # timeout, unavailable, busy, auth, bad_request, server_error, invalid_response
    attr_reader :category

    def initialize(message, category:)
      super(message)
      @category = category
    end
  end
end
