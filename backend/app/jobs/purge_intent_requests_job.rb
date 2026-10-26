# Recurring cleanup (see config/recurring.yml). The sentences users typed are personal data, so
# they are deleted after INTENT_RETENTION_DAYS (default 30). Plans that were executed keep their
# effect (keywords and runs) because those do not reference the sentence.
class PurgeIntentRequestsJob < ApplicationJob
  queue_as :default

  def perform
    deleted = IntentRequest.purge_expired
    Rails.logger.info("intent_purge deleted=#{deleted} retention_days=#{Intent::Config.retention_days}") if deleted.positive?
  end
end
