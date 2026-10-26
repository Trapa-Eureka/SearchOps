class RankSnapshotSerializer
  # comparison is a RankComparison::Result against the previous snapshot.
  def self.call(snapshot, comparison)
    {
      id: snapshot.id,
      search_run_id: snapshot.search_run_id,
      target_domain: snapshot.target_domain,
      rank: snapshot.rank,
      found: snapshot.found?,
      captured_at: snapshot.captured_at,
      comparison: {
        status: comparison.status,
        delta: comparison.delta,
        previous_rank: comparison.previous_rank
      }
    }
  end
end
