# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class DescribeStream < Base
      TRACE_NOTES = 'span fields: start_time/end_time are nanoseconds, duration is microseconds, ' \
                    "parent = reference_parent_span_id, errors have span_status = 'ERROR'."

      tool_name 'describe_stream'
      description 'Show the fields (grouped by type), document count, time range and full-text fields of a stream. ' \
                  'Use before writing `where` filters or SQL instead of guessing field names.'
      input_schema Schemas.input(Schemas::DescribeStream)

      def self.execute(runtime, stream:, type:, env: nil, org: nil)
        target = runtime.target(env: env, org: org)
        schema = runtime.with_stream_suggestions(target, stream, type: type) do
          runtime.stream_schema(target, stream, type: type)
        end

        fields = schema['schema'] || []
        lines = [summary(target, stream, type, fields, schema['stats'] || {})]
        full_text = schema.dig('settings', 'full_text_search_keys') || []
        lines << "full-text fields (used by search_logs text): #{full_text.any? ? full_text.join(', ') : 'OpenObserve defaults'}"
        fields.group_by { it['type'] }.sort_by { |_, group| -group.size }.each do |field_type, group|
          lines << "#{field_type} (#{group.size}): #{group.map { it['name'] }.sort.join(', ')}"
        end
        lines << TRACE_NOTES if type == 'traces'
        lines.join("\n")
      end

      def self.summary(target, stream, type, fields, stats)
        parts = ["#{target.label} #{stream} (#{type})", "#{fields.size} fields", Formatter.doc_count(stats['doc_num'])]
        if stats['doc_time_min'].to_i.positive?
          parts << "#{TimeRange.format_us(stats['doc_time_min'])} → #{TimeRange.format_us(stats['doc_time_max'])}"
        end
        parts.join(' · ')
      end
      private_class_method :summary
    end
  end
end
