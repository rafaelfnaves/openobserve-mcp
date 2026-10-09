# frozen_string_literal: true

module ObservabilityMcp
  # Renders the spans of one trace (OpenObserve traces stream rows) as an indented call tree.
  #
  # OpenObserve span rows store start_time/end_time in nanoseconds, duration in microseconds and the
  # parent in reference_parent_span_id. Error spans are marked with ✗ and show their exception and the
  # most relevant stack frames. Runs of identical sibling spans (N+1 queries, retries) are collapsed
  # unless an error sits anywhere below them. Rendering is iterative (deep chains cannot overflow the
  # stack), indentation stops at MAX_DEPTH, and spans caught in parent cycles are still shown.
  class TraceTree
    KEY_ATTRIBUTES = %w[
      http_method http_route http_url http_status_code db_system db_operation db_statement rpc_service
      rpc_method messaging_system messaging_destination_name gen_ai_request_model gen_ai_usage_total_tokens error_type
    ].freeze
    STRUCTURAL = %w[
      _timestamp trace_id span_id reference_parent_span_id reference_parent_trace_id reference_ref_type
      start_time end_time duration service_name operation_name span_status span_kind status_code status_message
      events links
    ].freeze
    STACK_LINES = 6
    COLLAPSE_AFTER = 3
    MAX_DEPTH = 40

    def initialize(spans, max_chars: 200, show_attributes: false)
      @spans = spans
      @max_chars = max_chars
      @show_attributes = show_attributes
      ids = spans.to_set { it['span_id'] }
      @children = spans.group_by { ids.include?(it['reference_parent_span_id']) ? it['reference_parent_span_id'] : :root }
      @orphans = spans.count { !it['reference_parent_span_id'].to_s.empty? && !ids.include?(it['reference_parent_span_id']) }
      @children.each_value { |list| list.sort_by! { it['start_time'].to_i } }
      @trace_start = spans.map { it['start_time'].to_i }.min
      @rendered = Set.new.compare_by_identity
    end

    def render
      lines = [header]
      render_forest(roots, lines)
      lines.join("\n")
    end

    private

    def header
      trace_end = @spans.map { it['end_time'].to_i }.max
      errors = @spans.count { error?(it) }
      services = @spans.map { it['service_name'] }.tally.map { |name, count| "#{name} (#{count})" }
      [
        "trace #{@spans.first['trace_id']} · #{@spans.size} spans · #{errors} errors",
        Formatter.duration_ms((trace_end - @trace_start) / 1_000),
        "started #{TimeRange.format_us(@trace_start / 1_000)}",
        "services: #{services.join(', ')}"
      ].join(' · ') + partial_notice
    end

    def partial_notice
      return '' if @orphans.zero?

      "\n⚠ partial trace: #{@orphans} spans point to parents that are not in this stream/window " \
        '(uninstrumented caller, other stream, or outside the time window)'
    end

    # Spans whose parent is absent, plus one entry point per group of spans that only reference each other
    # (a parent cycle), so every span is reachable from some root.
    def roots
      roots = @children.fetch(:root, [])
      reached = descendants(roots)
      @spans.sort_by { it['start_time'].to_i }.each_with_object(roots.dup) do |span, all|
        next if reached.include?(span)

        all << span
        reached.merge(descendants([span]))
      end
    end

    def children(span) = @children.fetch(span['span_id'], [])

    # The given spans and everything below them (cycle-safe, iterative).
    def descendants(spans)
      seen = Set.new.compare_by_identity
      stack = spans.dup
      while (span = stack.pop)
        stack.concat(children(span)) if seen.add?(span)
      end
      seen
    end

    # Depth-first, pre-order, with an explicit stack. Each entry renders a span (Hash) or a run of
    # identical siblings (Array) collapsed into one line.
    def render_forest(roots, lines)
      stack = entries(roots, '', nil, 0).reverse
      while (item, branch, continuation, parent_service, depth = stack.pop)
        if item.is_a?(Array)
          lines << branch + collapsed_line(item, parent_service)
          next
        end

        lines << branch + span_line(item, parent_service)
        error_details(item).each { lines << "#{continuation}  #{it}" } if error?(item)
        below = children(item).reject { @rendered.include?(it) }
        next if below.empty?

        if depth + 1 >= MAX_DEPTH
          lines << "#{continuation}└─ … #{descendants(below).size} deeper spans not shown (max depth #{MAX_DEPTH})"
        else
          stack.concat(entries(below, continuation, item['service_name'], depth + 1).reverse)
        end
      end
    end

    def entries(siblings, prefix, parent_service, depth)
      items = siblings.chunk_while { |a, b| same_kind?(a, b) }.flat_map do |group|
        group.size > COLLAPSE_AFTER && descendants(group).none? { error?(it) } ? [group] : group
      end
      items.each { |item| @rendered.merge(item.is_a?(Array) ? descendants(item) : [item]) }

      items.each_with_index.map do |item, index|
        last = index == items.size - 1
        [item, prefix + (last ? '└─ ' : '├─ '), prefix + (last ? '   ' : '│  '), parent_service, depth]
      end
    end

    def span_line(span, parent_service)
      parts = [error?(span) ? '✗' : nil, label(span, parent_service), duration(span), offset(span)]
      attributes = attributes(span)
      parts << "{#{attributes.map { |key, value| "#{key}=#{value}" }.join(' ')}}" if attributes.any?
      parts.compact.join(' ')
    end

    def collapsed_line(group, parent_service)
      durations = group.map { span_duration_us(it) }
      "×#{group.size} #{label(group.first, parent_service)} total=#{Formatter.duration_ms(durations.sum)} " \
        "max=#{Formatter.duration_ms(durations.max)} #{offset(group.first)} (repeated siblings collapsed)"
    end

    def label(span, parent_service)
      service = span['service_name']
      operation = span['operation_name'].to_s
      service && service != parent_service && service != operation ? "[#{service}] #{operation}" : operation
    end

    def duration(span) = Formatter.duration_ms(span_duration_us(span))

    def offset(span) = "@+#{Formatter.duration_ms((span['start_time'].to_i - @trace_start) / 1_000)}"

    def span_duration_us(span)
      span['duration']&.to_i || ((span['end_time'].to_i - span['start_time'].to_i) / 1_000)
    end

    def attributes(span)
      keys = @show_attributes ? span.keys - STRUCTURAL : KEY_ATTRIBUTES
      span.slice(*keys)
          .reject { |key, value| Formatter::EMPTY_VALUES.include?(value) || key.match?(Formatter::NOISE) }
          .to_h { |key, value| [key, Formatter.scalar(Formatter.redact(key, value), 120)] }
    end

    def error?(span) = span['span_status'] == 'ERROR' || span['status_code'].to_i == 2

    def error_details(span)
      exceptions = exceptions(span)
      status = span['status_message'].to_s
      details = []
      unless status.empty? || exceptions.any? { status.include?(it['exception.message'].to_s.lines.first.to_s.strip) }
        details << "status: #{one_line(status)}"
      end
      exceptions.each do |event|
        details << "exception #{event['exception.type']}: #{one_line(event['exception.message'])}"
        stack_frames(event['exception.stacktrace']).each { details << "  #{it}" }
      end
      details
    end

    # The same exception is often recorded once per instrumented layer; keep one of each.
    def exceptions(span)
      events = span['events']
      events = JSON.parse(events) if events.is_a?(String)
      Array(events).select { it.is_a?(Hash) && it['name'] == 'exception' }
                   .uniq { [it['exception.type'], it['exception.message']] }
    rescue JSON::ParserError
      []
    end

    # Python tracebacks put the failing frame last, as `File "x", line N, in f` + the source line;
    # most other runtimes (Ruby, Java, JS) put it first, one frame per line.
    def stack_frames(stacktrace)
      lines = stacktrace.to_s.lines.map(&:strip).reject(&:empty?)
      frames = if lines.first&.start_with?('Traceback')
                 lines.each_index.select { lines[it].start_with?('File "') }.last(STACK_LINES / 2).map do |index|
                   source = lines[index + 1]
                   source && !source.start_with?('File "') ? "#{lines[index]} → #{source}" : lines[index]
                 end
               else
                 lines.first(STACK_LINES)
               end
      frames.map { Formatter.truncate(it, @max_chars) }
    end

    def one_line(text) = Formatter.truncate(Formatter.redact(nil, text.to_s.strip.gsub(/\s*\r?\n\s*/, ' ⏎ ')), @max_chars)

    def same_kind?(a, b)
      a['service_name'] == b['service_name'] && a['operation_name'] == b['operation_name']
    end
  end
end
