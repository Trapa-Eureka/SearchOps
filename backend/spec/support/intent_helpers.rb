module IntentHelpers
  # Stands in for laya-serve in specs. Records what it was asked and answers as configured.
  class FakeClassifier
    attr_reader :calls

    def initialize(intent: "unsupported", confidence: 0.9, probabilities: nil, error: nil, model: "multilingual")
      @intent = intent
      @confidence = confidence
      @probabilities = probabilities
      @error = error
      @model = model
      @calls = []
    end

    def classify(text)
      @calls << text
      raise @error if @error

      Intent::Classification.new(intent: @intent, confidence: @confidence, probabilities: probabilities, model: @model, latency_ms: 12)
    end

    private

    def probabilities
      return @probabilities if @probabilities

      others = Intent::Catalog::INTENTS - [ @intent ]
      share = (1.0 - @confidence) / others.size
      Intent::Catalog::INTENTS.to_h { |label| [ label, label == @intent ? @confidence : share ] }
    end
  end

  def fake_classifier(**options)
    FakeClassifier.new(**options)
  end

  def classifier_error(category)
    Intent::ClassifierError.new("boom #{category}", category: category)
  end

  # A laya-serve response body for WebMock stubs, shaped like the recorded fixture.
  def laya_response_body(intent:, confidence: 0.9, model: "multilingual")
    body = JSON.parse(Rails.root.join("spec/fixtures/laya/systemone_response.json").read)
    others = Intent::Catalog::INTENTS - [ intent ]
    probabilities = Intent::Catalog::INTENTS.to_h { |label| [ label, label == intent ? confidence : ((1.0 - confidence) / others.size) ] }
    body["answers"]["intent"].merge!("choice" => intent, "probabilities" => probabilities, "confidence" => confidence)
    body["routing"]["model"] = model
    body
  end

  def stub_laya(intent: "organic_rank_tracking", confidence: 0.9, url: "http://127.0.0.1:8765/v1/systemone", status: 200, body: nil)
    stub_request(:post, url).to_return(status: status, body: (body || laya_response_body(intent: intent, confidence: confidence)).then { |b| b.is_a?(String) ? b : b.to_json },
                                       headers: { "Content-Type" => "application/json" })
  end
end

RSpec.configure do |config|
  config.include IntentHelpers
  # Hits a real laya-serve on localhost. Opt in with LAYA_LIVE=1 (see docs/laya-contract.md).
  config.filter_run_excluding :laya_live unless ENV["LAYA_LIVE"]
end

# The per-IP planning limit is stored in memory for the whole process; start every example clean.
module IntentsControllerReset
  def self.call
    Api::V1::IntentsController::RATE_STORE.clear
  end
end
