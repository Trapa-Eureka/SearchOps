module Intent
  # What the planner may propose. Anything outside these lists is rejected by the validator,
  # so a classifier cannot ask for an action that does not exist here.
  module Catalog
    INTENTS = %w[organic_rank_tracking job_search search_history unsupported].freeze

    # Intent -> the SerpApi engine it needs. google_jobs is recognized but not implemented.
    ENGINES = {
      "organic_rank_tracking" => "google",
      "job_search" => "google_jobs",
      "search_history" => "google"
    }.freeze

    # Fields a client may edit when confirming a plan. The intent itself cannot be changed.
    EDITABLE_FIELDS = %w[query country language location target_domain compare_previous only_new].freeze
    PLAN_FIELDS = (EDITABLE_FIELDS + %w[intent engine keyword_id]).freeze

    # The questions sent to laya-serve (contract read from laya/serve.py, see docs/laya-contract.md).
    # Wording was compared on the dev split of the evaluation set: the plain descriptions scored
    # 72.9%, the longer disambiguating variants 59-63%, so this is deliberately the simple one.
    INTENT_QUESTION = {
      "type" => "choice",
      "instructions" => "What does the user want to do?",
      "criteria" => {
        "organic_rank_tracking" => "check or track where a website or domain ranks in web search results for a keyword",
        "job_search" => "find job postings or job listings",
        "search_history" => "look at past search results, saved snapshots, or how a ranking changed over time",
        "unsupported" => "anything else, or unclear"
      }
    }.freeze

    # Laya is asked one question only. It was also asked two yes/no questions (compare with an
    # earlier result? only new items?), but its scores added false positives and found nothing
    # the word lists in Intent::Lexicon had missed, on both evaluation splits, so the flags come
    # from the rules alone. See docs/intent-eval.md.
    def self.questions
      { "intent" => INTENT_QUESTION }
    end
  end
end
