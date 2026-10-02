# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class FieldValues < Base
      tool_name 'field_values'
      description 'Most frequent values of one field with their counts — the cheapest way to see which services, ' \
                  'severities, status codes, error types or workers appear in a window before reading records.'
      input_schema Schemas.input(Schemas::FieldValues)

      def self.execute(runtime, stream:, field:, type:, since:, limit:, env: nil, org: nil, where: nil, from: nil,
                       to: nil)
        target = runtime.target(env: env, org: org)
        range = time_range(since: since, from: from, to: to)
        column = SearchQuery.ident(field)
        sql = SearchQuery.select(stream: stream, columns: ["#{column} AS \"value\"", 'count(*) AS "count"'],
                                 where: [where], group_by: column, order_by: '"count" DESC', limit: limit)

        response = search(runtime, target, SearchQuery.new(sql, time_range: range, size: limit), type: type, stream: stream)
        hits = response['hits'] || []
        return empty_result(target, range, "values of #{field} in #{stream}") if hits.empty?

        width = Formatter.number(hits.map { it['count'] }.max).length
        lines = ["#{field} · #{target.label} #{stream} (#{type}) · window #{range} · top #{hits.size}"]
        hits.each do |hit|
          value = hit['value'].nil? ? '(null)' : Formatter.scalar(hit['value'], 200)
          lines << "#{Formatter.number(hit['count']).rjust(width)}  #{value}"
        end
        lines.join("\n")
      end
    end
  end
end
