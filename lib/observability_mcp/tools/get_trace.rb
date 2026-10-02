# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class GetTrace < Base
      tool_name 'get_trace'
      description 'Show every span of one trace as a call tree with durations and offsets. Error spans are marked ✗ ' \
                  'with their exception and key stack frames; repeated sibling spans (N+1 queries) are collapsed. ' \
                  'The window defaults to the last 24h — pass from/to around the trace time for older traces.'
      input_schema Schemas.input(Schemas::GetTrace)

      def self.execute(runtime, trace_id:, stream:, since:, max_spans:, show_attributes:, max_chars:, env: nil, org: nil,
                       from: nil, to: nil)
        target = runtime.target(env: env, org: org)
        range = time_range(since: since, from: from, to: to)
        sql = SearchQuery.select(stream: stream, where: ["trace_id = #{SearchQuery.literal(trace_id.downcase)}"],
                                 order_by: 'start_time ASC', limit: max_spans + 1)

        response = search(runtime, target, SearchQuery.new(sql, time_range: range, size: max_spans + 1),
                          type: 'traces', stream: stream)
        spans = response['hits'] || []
        return empty_result(target, range, "spans for trace #{trace_id}") if spans.empty?

        tree = TraceTree.new(spans.first(max_spans), max_chars: max_chars, show_attributes: show_attributes).render
        return tree if spans.size <= max_spans

        "#{tree}\n⚠ more than #{max_spans} spans; showing the earliest #{max_spans}. Raise max_spans or use run_sql."
      end
    end
  end
end
