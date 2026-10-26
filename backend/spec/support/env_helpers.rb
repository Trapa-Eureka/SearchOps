# Tag an example or group with `env: { "NAME" => "value" }` to set environment
# variables for its duration (nil removes one). The originals are restored afterwards.
RSpec.configure do |config|
  config.around do |example|
    overrides = example.metadata[:env]
    if overrides
      originals = overrides.keys.index_with { |name| ENV.fetch(name, nil) }
      overrides.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    end

    begin
      example.run
    ensure
      originals&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    end
  end
end
