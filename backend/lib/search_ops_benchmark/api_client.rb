module SearchOpsBenchmark
  # Talks to the real Rails stack (routing, controllers, serialization, jobs) in-process, as a
  # browser would, and times each request. Only the network below it is replaced.
  class ApiClient
    Result = Data.define(:status, :body, :ms)

    def initialize(session: ActionDispatch::Integration::Session.new(Rails.application))
      @session = session
      @session.host! "localhost"
    end

    def plan(text)
      request(:post, "/api/v1/intent/plan", { text: text })
    end

    def confirm(plan_id, edits = nil)
      request(:post, "/api/v1/intent/plan/#{plan_id}/confirm", edits ? { plan: edits } : {})
    end

    def create_keyword(task)
      request(:post, "/api/v1/keywords", { keyword: task })
    end

    def search(keyword_id)
      request(:post, "/api/v1/keywords/#{keyword_id}/searches", {})
    end

    private

    def request(verb, path, params)
      # The planning endpoint limits requests per IP; that limiter has its own specs, and a
      # benchmark sending hundreds of sentences from one address would only measure it.
      Api::V1::IntentsController::RATE_STORE.clear
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @session.public_send(verb, path, params: params, as: :json)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000)
      body = @session.response.body.to_s
      Result.new(status: @session.response.status, body: body.empty? ? {} : JSON.parse(body), ms: ms)
    end
  end
end
