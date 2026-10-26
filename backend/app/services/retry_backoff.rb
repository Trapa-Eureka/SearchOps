# Delay before retrying a transient failure: capped exponential backoff with jitter.
#
# The ceiling doubles per attempt (BASE, 2*BASE, 4*BASE, ...) up to CAP, and the actual
# delay is random between half of it and all of it ("equal jitter"), so workers that failed
# together do not all retry at the same instant. A Retry-After hint from the server, when
# there is one, wins but is capped so a bad value cannot park a run for hours.
class RetryBackoff
  BASE_SECONDS = 2
  CAP_SECONDS = 60
  MAX_RETRY_AFTER_SECONDS = 300

  # attempt is the number of attempts already made (1 after the first failure).
  def self.delay(attempt, retry_after: nil, random: Random)
    return [ retry_after, MAX_RETRY_AFTER_SECONDS ].min if retry_after&.positive?

    ceiling = [ BASE_SECONDS * (2**(attempt.to_i - 1)), CAP_SECONDS ].min
    (ceiling / 2.0) + (random.rand * ceiling / 2.0)
  end
end
