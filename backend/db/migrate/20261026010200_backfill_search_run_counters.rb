# Runs recorded before attempts/upstream_calls existed (Stage 3) really did call SerpApi once.
# Without this their calls are invisible to the daily budget and the metrics.
class BackfillSearchRunCounters < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE search_runs
      SET attempts = 1, upstream_calls = 1
      WHERE cache_source = 'none' AND status IN ('succeeded', 'failed') AND upstream_calls = 0 AND attempts = 0
        AND error_category IS DISTINCT FROM 'budget' AND error_category IS DISTINCT FROM 'abandoned'
    SQL
  end

  def down
    # Not reversible: the original zeros were placeholders, not data.
  end
end
