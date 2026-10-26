module SearchOpsBenchmark
  # The benchmark deletes every keyword and run between modes. It therefore refuses to start on
  # any database whose name does not end in an allowed suffix (a dedicated scratch database),
  # so it can never wipe real data.
  module DatabaseGuard
    class Refused < StandardError; end

    module_function

    def check!(allowed_suffixes: %w[_bench])
      name = ActiveRecord::Base.connection.current_database
      return name if allowed_suffixes.any? { |suffix| name.end_with?(suffix) }

      raise Refused, "refusing to run on database #{name.inspect}: it must end in #{allowed_suffixes.join(' or ')}. " \
                     "Create a scratch database and point DATABASE_URL at it (postgresql:///searchops_bench)."
    end

    def wipe!
      [ RankSnapshot, SearchResult, SearchRun, IntentRequest, Keyword ].each(&:delete_all)
    end
  end
end
