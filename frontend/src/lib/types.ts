// Shapes of the Rails API responses (see docs/api-contract.md). Only fields the UI reads.

export type PageMeta = { page: number; per_page: number; total_count: number; total_pages: number };
export type Paginated<T> = { data: T[]; meta: PageMeta };

export type FreshnessState = "fresh" | "stale" | "no_data";
export type Freshness = {
  state: FreshnessState;
  reason: "last_attempt_failed" | "overdue" | null;
  last_success_at: string | null;
  last_attempt_status: "succeeded" | "failed" | null;
  last_attempt_at: string | null;
};

export type Schedule = "manual" | "daily" | "weekly";
export type Keyword = {
  id: number;
  query: string;
  engine: string;
  country: string;
  language: string;
  location: string | null;
  target_domain: string | null;
  active: boolean;
  schedule: Schedule;
  created_at: string;
  updated_at: string;
  freshness?: Freshness;
};
export type KeywordInput = {
  query: string;
  engine?: string;
  country: string;
  language: string;
  location?: string | null;
  target_domain?: string | null;
  active?: boolean;
  schedule?: Schedule;
};

export type RunStatus = "queued" | "running" | "succeeded" | "failed";
export type ErrorCategory =
  | "auth" | "quota" | "rate_limit" | "network" | "timeout" | "invalid_request"
  | "schema" | "upstream" | "unknown" | "budget" | "abandoned";
export type AttemptLogEntry = { attempt: number; category: string; http_status: number | null; message: string };

export type SearchResultRow = {
  position: number;
  title: string | null;
  url: string;
  display_domain: string | null;
  snippet: string | null;
};
export type RunRank = { target_domain: string; rank: number | null; found: boolean };
export type Run = {
  id: number;
  keyword_id: number;
  status: RunStatus;
  triggered_by: "manual" | "scheduled";
  started_at: string | null;
  finished_at: string | null;
  attempts: number;
  upstream_calls: number;
  upstream_latency_ms: number | null;
  http_status: number | null;
  error_category: ErrorCategory | null;
  error_message: string | null;
  attempt_log: AttemptLogEntry[];
  cache_source: "none" | "app" | "serpapi";
  cache: { hit: boolean; source_run_id: number | null; age_seconds: number | null };
  result_count: number | null;
  empty_results: boolean | null;
  request: { provider?: string; engine?: string; query?: string; country?: string; language?: string; location?: string | null; search_id?: string | null };
  rank: RunRank | null;
  created_at: string;
  results?: SearchResultRow[];
  keyword?: { id: number; query: string; country: string; language: string; target_domain: string | null };
};
export type SearchOutcome = "enqueued" | "deduplicated" | "cache_hit";
export type SearchStarted = { data: Run; meta: { outcome: SearchOutcome } };

export type ComparisonStatus =
  | "improved" | "declined" | "unchanged" | "entered" | "dropped" | "not_found" | "not_comparable" | "baseline";
export type RankHistoryEntry = {
  id: number;
  search_run_id: number;
  target_domain: string;
  rank: number | null;
  found: boolean;
  captured_at: string;
  comparison: { status: ComparisonStatus; delta: number | null; previous_rank: number | null };
};
export type RankHistory = {
  data: RankHistoryEntry[];
  meta: PageMeta & {
    target_domain: string | null;
    ordering: "newest_first";
    rank_semantics: "lower_is_better";
    null_rank_meaning: "not_found_in_retrieved_window";
    freshness: Freshness;
  };
};

export type Latency = { samples: number; p50: number | null; p95: number | null; max: number | null };
export type Metrics = {
  window: { name: string; from: string; to: string };
  requests: { total: number; by_status: Record<RunStatus, number>; by_trigger: Record<"manual" | "scheduled", number> };
  upstream: { calls: number; retries: number; runs_succeeded: number; runs_failed: number; success_rate: number | null; latency_ms: Latency };
  cache: { hits: number; misses: number; hit_rate: number | null; ttl_seconds: number };
  errors: Record<string, number>;
  budget: { daily_limit: number; used_today: number; remaining_today: number };
  keywords: { total: number; active: number; scheduled: number; stale: number; no_data: number };
  queue: { queued: number; running: number; oldest_queued_age_seconds: number | null; workers_alive: number };
  intent: {
    enabled: boolean;
    requests: number;
    by_outcome: Record<string, number>;
    fallbacks: Record<string, number>;
    laya_latency_ms: Latency;
  };
};

export type Options = {
  engines: string[];
  countries: string[];
  languages: string[];
  schedules: Schedule[];
  limits: { query_max_length: number; location_max_length: number; max_keywords: number; intent_text_max_length: number; max_per_page: number };
  features: { intent_planning: boolean };
};

export type IntentName = "organic_rank_tracking" | "job_search" | "search_history" | "unsupported";
export type PlanStatus = "ready" | "needs_clarification" | "unsupported" | "unavailable" | "executed";
export type PlanFields = {
  intent?: IntentName;
  engine?: string;
  query?: string;
  country?: string;
  language?: string;
  location?: string;
  target_domain?: string;
  keyword_id?: number;
  compare_previous?: boolean;
  only_new?: boolean;
};
export type FieldProvenance = { source: "laya" | "rule" | "missing" | "default"; evidence?: string | null; confidence?: number; derived_from?: string | null; scope?: string };
export type IntentPlan = {
  id: number;
  status: PlanStatus;
  reason: string | null;
  next_step: "confirm" | "complete_fields" | "rephrase_or_use_structured_input" | "use_structured_input" | "none";
  plan: PlanFields | null;
  requires_confirmation: boolean;
  missing: string[];
  errors: Record<string, string>;
  fields: Record<string, FieldProvenance>;
  candidates: { intent: IntentName; probability: number }[];
  keyword_candidates: { id: number; query: string; target_domain: string | null }[];
  query_suggestions: string[];
  history: { keyword_id: number | null; snapshots: number } | null;
  notes: string[];
  classifier: { name: string; enabled: boolean; version?: string; intent?: IntentName; confidence?: number; probabilities?: Record<string, number>; min_confidence?: number; latency_ms?: number };
  structured_input: { endpoint: string; fields: string[]; prefill: { query?: string; country?: string; language?: string; target_domain?: string } } | null;
  execution: { kind: "search"; keyword_id: number; keyword_created: boolean; run_id: number; search_outcome: SearchOutcome } | { kind: "history"; keyword_id: number | null } | null;
  created_at: string;
  confirmed_at: string | null;
};
