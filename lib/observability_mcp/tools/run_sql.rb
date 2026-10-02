# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class RunSql < Base
      tool_name 'run_sql'
      description 'Run a read-only SQL query (aggregations, GROUP BY, histograms, joins) against OpenObserve. ' \
                  'The time window comes from since/from/to; stream names are quoted and a LIMIT added automatically. ' \
                  'Set `type` to the stream type (spans: type="traces"). Example: SELECT histogram(_timestamp, ' \
                  '\'5 minute\') AS t, count(*) AS n FROM default GROUP BY t ORDER BY t'
      input_schema Schemas.input(Schemas::RunSql)

      def self.execute(runtime, sql:, type:, since:, limit:, max_chars:, env: nil, org: nil, from: nil, to: nil)
        target = runtime.target(env: env, org: org)
        range = time_range(since: since, from: from, to: to)
        normalized = SearchQuery.normalize(sql, limit: limit)

        response = search(runtime, target, SearchQuery.new(normalized, time_range: range, size: limit), type: type)
        all_hits = response['hits'] || []
        hits = all_hits.first(limit)
        lines = [Formatter.search_header(response, shown: hits.size, time_range: range, source: "#{target.label} (#{type})")]
        lines << "sql (normalized): #{normalized}" unless normalized == sql.strip
        lines << "⚠ #{all_hits.size} rows returned; showing the first #{limit} (raise `limit` to see more)" if all_hits.size > limit
        lines << (hits.empty? ? empty_result(target, range, 'rows') : Formatter.rows(hits, max_chars: max_chars))
        lines.join("\n")
      end
    end
  end
end
