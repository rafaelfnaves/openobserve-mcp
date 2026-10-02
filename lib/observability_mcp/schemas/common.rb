# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    # Fragments shared by tool schemas. `extend Common` inside a Schematist::Schema and call them in the class body.
    module Common
      STREAM_TYPES = %w[logs traces metrics].freeze

      def target_params
        string :env, required: false,
                     description: 'OpenObserve environment, e.g. "staging" or "prod". Defaults to OO_DEFAULT_ENV.'
        string :org, required: false,
                     description: 'Organization, e.g. "cilia-web" or "serverless". Defaults to OO_<ENV>_ORG / OO_DEFAULT_ORG.'
      end

      def time_window_params(default:)
        string :since, required: false, default: default,
                       description: 'Relative window ending at `to` (or now): 15m, 1h, 24h, 7d. Ignored when `from` is set.'
        string :from, required: false,
                      description: 'Absolute window start: ISO8601 (2026-10-01T12:00:00Z; without an offset it is UTC), ' \
                                   'Unix epoch in s/ms/µs/ns, or relative ("2h" or "2h ago"). Max window 31d.'
        string :to, required: false, description: 'Window end, same formats as `from`. Default now.'
      end

      def stream_param(description: 'Stream name exactly as listed by list_streams (no quotes needed).')
        string :stream, description: description
      end

      def stream_type_param(default: 'logs')
        string :type, required: false, enum: STREAM_TYPES, default: default,
                      description: 'Type of the stream; must match it. The same name can exist as both logs and ' \
                                   'traces (e.g. "default"), so pass "traces" to query spans.'
      end

      def where_param
        string :where, required: false,
                       description: "Extra SQL condition, e.g. \"severity = 'ERROR' AND service_name LIKE '%search%'\". " \
                                    'Use describe_stream for field names; quote strings with single quotes.'
      end

      def limit_param(default:, maximum:, description: 'Max rows returned.')
        integer :limit, required: false, minimum: 1, maximum: maximum, default: default, description: description
      end

      def max_chars_param(default: Formatter::DEFAULT_MAX_CHARS)
        integer :max_chars, required: false, minimum: 40, maximum: 5_000, default: default,
                            description: 'Truncate each value to this many characters (raise it to read full stack traces).'
      end
    end
  end
end
