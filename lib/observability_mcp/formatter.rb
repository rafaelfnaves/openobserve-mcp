# frozen_string_literal: true

module ObservabilityMcp
  # Turns OpenObserve hits into compact text: empty values dropped, long values truncated,
  # telemetry boilerplate hidden and `_timestamp` rendered as ISO8601. Uniform narrow rows
  # (aggregations) become a table; wide or sparse rows (raw logs/spans) become one line per record.
  module Formatter
    module_function

    DEFAULT_MAX_CHARS = 300
    TABLE_MAX_COLUMNS = 8
    EMPTY_VALUES = [nil, '', '[]', '{}'].freeze
    # Shipper metadata that repeats on every record and rarely helps an investigation:
    # OpenTelemetry resource attributes and Filebeat/ECS bookkeeping (host_name is kept).
    NOISE = /\A(?:service_)*(?:telemetry_sdk_\w+|cloud_account_id|cloud_provider|service_instance_id|faas_version|
              instrumentation_library_\w+|instrumentation_scope_\w+|dropped_\w+_count|flags|
              agent_(?:ephemeral_id|id|name|type|version)|ecs_version|_version|input_type|timestamp_ingestion|
              log_offset|log_file_(?:device_id|fingerprint|inode))\z/x
    # Credential-like keys, matched as whole words of the snake_cased key ("accessToken", "X-Api-Key", "client_secret";
    # not "total_tokens"). Their values are masked, also inside nested JSON, before anything reaches the model.
    SENSITIVE_KEY = /(?:\A|_)(?:password|passwd|secret|token|api_?key|authorization|cookie|credentials?|private_key|
                     session_?id)(?:\z|_)/x
    AUTH_HEADER_VALUE = %r{\b(Bearer|Basic)\s+[\w\-.~+/]+=*}i
    REDACTED = '[REDACTED]'

    def rows(hits, fields: nil, max_chars: DEFAULT_MAX_CHARS)
      rows = hits.map { compact_row(it, fields: fields) }
      return '' if rows.empty?
      return "(#{rows.size} rows, all fields empty)" if rows.all?(&:empty?)

      columns = rows.map(&:keys).uniq
      if columns.one? && columns.first.size <= TABLE_MAX_COLUMNS
        table(rows, max_chars: max_chars)
      else
        records(rows, max_chars: max_chars)
      end
    end

    # "staging/serverless default (logs) · 20 of 4445 rows · 41ms · window ..." plus a warning when
    # OpenObserve returned partial results.
    def search_header(response, shown:, time_range:, source:)
      parts = [source, "#{shown} of #{response['total'] || shown} rows", "#{response['took']}ms", "window #{time_range}"]
      header = parts.join(' · ')
      response['is_partial'] ? "#{header}\n⚠ partial results: #{response['function_error'] || 'query hit a limit'}" : header
    end

    def compact_row(row, fields: nil)
      row = row.slice(*fields) if fields&.any?
      row.reject { |key, value| EMPTY_VALUES.include?(value) || (!fields&.any? && key.match?(NOISE)) }
    end

    def table(rows, max_chars:)
      columns = rows.first.keys
      lines = [columns.join(' | ')]
      rows.each { |row| lines << columns.map { value(it, row[it], max_chars) }.join(' | ') }
      lines.join("\n")
    end

    # One line per record. Fields with the same value in every record are printed once on a `common:` line.
    def records(rows, max_chars:)
      common = rows.size > 1 ? shared_fields(rows.map { it.except('_timestamp') }) : {}
      lines = common.empty? ? [] : ["common: #{pairs(common, max_chars).join(' | ')}"]
      rows.each do |row|
        fields = pairs(row.except('_timestamp', *common.keys), max_chars)
        fields = ['(all fields empty)'] if row.empty?
        lines << [row.key?('_timestamp') ? value('_timestamp', row['_timestamp'], max_chars) : nil, *fields].compact.join(' | ')
      end
      lines.join("\n")
    end

    def shared_fields(rows) = rows.reduce { |shared, row| shared.select { |key, value| row[key] == value } }

    def pairs(row, max_chars) = row.map { |key, raw| "#{key}=#{value(key, raw, max_chars)}" }

    def value(key, raw, max_chars)
      key == '_timestamp' && raw.is_a?(Integer) ? TimeRange.format_us(raw) : scalar(redact(key, raw), max_chars)
    end

    # Masks values stored under credential-like keys (recursively) and Bearer/Basic tokens in free text.
    def redact(key, raw)
      return REDACTED if sensitive_key?(key)

      case raw
      when Hash then raw.to_h { |nested_key, value| [nested_key, redact(nested_key, value)] }
      when Array then raw.map { redact(nil, it) }
      when String then raw.gsub(AUTH_HEADER_VALUE, "\\1 #{REDACTED}")
      else raw
      end
    end

    def sensitive_key?(key)
      !key.nil? && key.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.tr('-. ', '_').match?(SENSITIVE_KEY)
    end

    # Any JSON value as one truncated line.
    def scalar(raw, max_chars)
      text = raw.is_a?(String) ? raw : JSON.generate(raw)
      truncate(text.gsub(/\r?\n/, '\n'), max_chars)
    end

    def truncate(text, max_chars)
      text.length > max_chars ? "#{text[0, max_chars]}…(+#{text.length - max_chars} chars)" : text
    end

    def duration_ms(microseconds)
      ms = microseconds.to_f / 1_000
      ms >= 1_000 ? "#{(ms / 1_000).round(2)}s" : "#{ms.round(1)}ms"
    end

    # OpenObserve's stream stats are kept incrementally and can drift (even below zero) after retention runs.
    def doc_count(value) = value.to_i.negative? ? 'doc count unavailable' : "#{number(value)} docs"

    # 1234567 → "1,234,567"; keeps the sign and any fraction; nil → "0".
    def number(value)
      text = (value || 0).to_s
      integer, fraction = text.delete_prefix('-').split('.', 2)
      "#{'-' if text.start_with?('-')}#{integer.reverse.scan(/\d{1,3}/).join(',').reverse}#{".#{fraction}" if fraction}"
    end
  end
end
