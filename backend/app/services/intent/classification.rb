module Intent
  # What a classifier returns. probabilities covers every intent label; confidence is the
  # probability of the chosen one.
  Classification = Data.define(:intent, :confidence, :probabilities, :model, :latency_ms)
end
