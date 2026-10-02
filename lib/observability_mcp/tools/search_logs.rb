# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class SearchLogs < Base
      tool_name 'search_logs'
      description 'Fetch recent records from a stream with optional full-text `text` and SQL `where` filters. ' \
                  'Output is one compact line per record (empty values and telemetry boilerplate removed). ' \
                  'Prefer field_values to get an overview and `fields` to return only what you need.'
      input_schema Schemas.input(Schemas::SearchLogs)

      def self.execute(runtime, stream:, type:, since:, limit:, order:, max_chars:, env: nil, org: nil, text: nil,
                       where: nil, fields: nil, from: nil, to: nil)
        target = runtime.target(env: env, org: org)
        range = time_range(since: since, from: from, to: to)
        conditions = [where]
        conditions << "match_all(#{SearchQuery.literal(text)})" if text
        fields = (['_timestamp', *fields].uniq if fields&.any?)
        columns = fields&.map { SearchQuery.ident(it) }
        sql = SearchQuery.select(stream: stream, columns: columns, where: conditions,
                                 order_by: "_timestamp #{order == 'asc' ? 'ASC' : 'DESC'}", limit: limit)

        response = search(runtime, target, SearchQuery.new(sql, time_range: range, size: limit), type: type, stream: stream)
        hits = response['hits'] || []
        return "#{empty_result(target, range, 'records')}\nsql: #{sql}" if hits.empty?

        source = "#{target.label} #{stream} (#{type})"
        [Formatter.search_header(response, shown: hits.size, time_range: range, source: source), "sql: #{sql}",
         Formatter.rows(hits, fields: fields, max_chars: max_chars)].join("\n")
      end
    end
  end
end
