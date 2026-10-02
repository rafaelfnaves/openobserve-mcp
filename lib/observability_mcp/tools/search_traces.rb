# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class SearchTraces < Base
      tool_name 'search_traces'
      description 'Find recent traces, one line each: start, duration, span and error counts, services, root ' \
                  'operation and trace_id. Filter by service, operation, errors_only, min_duration_ms or `where` ' \
                  '(span-level SQL condition). Then open one with get_trace.'
      input_schema Schemas.input(Schemas::SearchTraces)

      def self.execute(runtime, stream:, errors_only:, since:, limit:, env: nil, org: nil, service: nil, operation: nil,
                       min_duration_ms: nil, where: nil, from: nil, to: nil)
        target = runtime.target(env: env, org: org)
        range = time_range(since: since, from: from, to: to)
        filter = build_filter(service: service, operation: operation, errors_only: errors_only,
                              min_duration_ms: min_duration_ms, where: where)

        response = runtime.with_stream_suggestions(target, stream, type: 'traces') do
          target.client.latest_traces(target.org, stream, start_time: range.start_us, end_time: range.end_us,
                                                          from: 0, size: limit, filter: filter)
        end
        traces = response['hits'] || []
        return empty_result(target, range, "traces#{" matching #{filter}" if filter}") if traces.empty?

        lines = ["#{traces.size} traces · #{target.label} #{stream} · window #{range}"]
        traces.each { lines << trace_line(it) }
        lines.join("\n")
      end

      def self.build_filter(service:, operation:, errors_only:, min_duration_ms:, where:)
        conditions = []
        conditions << "service_name = #{SearchQuery.literal(service)}" if service
        conditions << "operation_name = #{SearchQuery.literal(operation)}" if operation
        conditions << "span_status = 'ERROR'" if errors_only
        conditions << "duration >= #{(min_duration_ms * 1_000).to_i}" if min_duration_ms
        conditions << where if where && !where.strip.empty?
        conditions.empty? ? nil : conditions.map { "(#{it})" }.join(' AND ')
      end

      def self.trace_line(trace)
        total, errors = Array(trace['spans'])
        services = Array(trace['service_name']).map { "#{it['service_name']}(#{it['count']})" }
        root = trace.dig('first_event', 'operation_name')
        [
          TimeRange.format_us(trace['start_time'].to_i / 1_000),
          Formatter.duration_ms(trace['duration'].to_i),
          "#{total} spans",
          errors.to_i.positive? ? "✗ #{errors} errors" : nil,
          services.join(', '),
          root && !services.any? { it.start_with?("#{root}(") } ? "root=#{root}" : nil,
          "trace_id=#{trace['trace_id']}"
        ].compact.join(' · ')
      end
      private_class_method :build_filter, :trace_line
    end
  end
end
