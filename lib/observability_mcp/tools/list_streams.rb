# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class ListStreams < Base
      METRIC_SUFFIX = /_(?:bucket|count|sum|min|max)\z/

      tool_name 'list_streams'
      description 'List the streams of an org grouped by type (logs, traces, metrics) with document counts and the ' \
                  'time of the latest record. Metric families (x, x_bucket, x_count, ...) are collapsed into one line.'
      input_schema Schemas.input(Schemas::ListStreams)

      def self.execute(runtime, env: nil, org: nil, type: nil, filter: nil)
        target = runtime.target(env: env, org: org)
        streams = runtime.streams(target, type: type)
        streams = streams.reject { it['stream_type'] == 'metadata' } unless type
        streams = streams.select { it['name'].downcase.include?(filter.downcase) } if filter
        return "No streams in #{target.label}#{" matching '#{filter}'" if filter}." if streams.empty?

        lines = ["#{target.label} · #{streams.size} streams"]
        streams.group_by { it['stream_type'] }.sort.each do |stream_type, group|
          lines << "#{stream_type}:"
          entries = stream_type == 'metrics' ? metric_families(group) : group.sort_by { it['name'] }.map { stream_line(it) }
          entries.each { lines << "  #{it}" }
        end
        lines.join("\n")
      end

      def self.stream_line(stream)
        stats = stream['stats'] || {}
        return "#{stream['name']} · empty" if stats['doc_num'].to_i.zero? && stats['doc_time_max'].to_i.zero?

        "#{stream['name']} · #{Formatter.doc_count(stats['doc_num'])} · last #{TimeRange.format_us(stats['doc_time_max'])}"
      end

      def self.metric_families(streams)
        names = streams.to_set { it['name'] }
        families = streams.group_by do |stream|
          base = stream['name'].sub(METRIC_SUFFIX, '')
          names.include?(base) ? base : stream['name']
        end

        families.sort.map do |base, members|
          suffixes = members.map { it['name'].delete_prefix(base) }.reject(&:empty?).sort
          last = members.filter_map { it.dig('stats', 'doc_time_max') }.max
          line = suffixes.empty? ? base : "#{base} (+#{suffixes.join(' ')})"
          last.to_i.positive? ? "#{line} · last #{TimeRange.format_us(last)}" : line
        end
      end
      private_class_method :stream_line, :metric_families
    end
  end
end
