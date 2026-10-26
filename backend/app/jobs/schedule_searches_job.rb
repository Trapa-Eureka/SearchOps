# Recurring tick (see config/recurring.yml): enqueue a search for every scheduled keyword
# that is due. Never touches Laya. Safe to run twice: SearchEnqueuer deduplicates active
# runs and reuses a fresh cache entry, so a double-fired tick costs nothing.
class ScheduleSearchesJob < ApplicationJob
  queue_as :default

  def perform
    unless Providers::SerpApiSearchProvider.configured?
      Rails.logger.warn("schedule_skipped reason=provider_not_configured")
      return
    end

    due = Keyword.due_for_check
    enqueuer = SearchEnqueuer.new
    outcomes = Hash.new(0)

    due.each do |keyword|
      outcomes[enqueuer.call(keyword, triggered_by: "scheduled").outcome] += 1
    rescue SearchBudget::Exceeded
      # Stop for the day instead of creating a failed run for every remaining keyword.
      Rails.logger.warn("schedule_budget_exhausted due=#{due.size} enqueued=#{outcomes[:enqueued]}")
      break
    end

    Rails.logger.info("schedule_tick due=#{due.size} #{outcomes.map { |name, count| "#{name}=#{count}" }.join(' ')}".strip)
  end
end
