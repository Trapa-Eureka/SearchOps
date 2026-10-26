module SearchOpsBenchmark
  # Small, dependency-free statistics for the report. Everything returns nil for "no data"
  # instead of 0, so a missing measurement is never shown as a good one.
  module Stats
    module_function

    # Linear interpolation between ranks, the same method as MetricsSummary.
    def percentile(values, fraction)
      sorted = values.compact.sort
      return nil if sorted.empty?

      position = fraction * (sorted.size - 1)
      lower = sorted[position.floor]
      upper = sorted[position.ceil]
      lower + ((upper - lower) * (position - position.floor))
    end

    def mean(values)
      list = values.compact
      list.empty? ? nil : list.sum.to_f / list.size
    end

    def summary(values)
      list = values.compact
      { n: list.size, p50: percentile(list, 0.5), p95: percentile(list, 0.95), max: list.max, mean: mean(list) }
    end

    # 95% Wilson score interval for a proportion. With samples this small a plain
    # "x out of n" would look more certain than it is.
    def wilson(successes, total, z: 1.96)
      return nil if total.nil? || total.zero?

      p = successes.to_f / total
      denominator = 1 + (z**2 / total)
      centre = (p + (z**2 / (2 * total))) / denominator
      margin = z * Math.sqrt(((p * (1 - p)) / total) + (z**2 / (4 * total**2))) / denominator
      [ [ centre - margin, 0.0 ].max, [ centre + margin, 1.0 ].min ]
    end

    def rate(successes, total)
      total.to_i.zero? ? nil : successes.to_f / total
    end
  end
end
