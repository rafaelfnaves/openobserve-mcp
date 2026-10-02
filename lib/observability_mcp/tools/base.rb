# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    # Every tool is read-only, returns compact text, and reports problems as an MCP error result with an
    # actionable message. Unexpected exceptions are logged to stderr and reported as errors too; left alone,
    # the SDK would turn them into an opaque "Internal error" and log nothing.
    #
    # Subclasses implement `execute(runtime, **arguments)` and return a String. Arguments arrive with the
    # input schema defaults applied, so the schema is the single source of truth for default values.
    class Base < MCP::Tool
      class << self
        def inherited(subclass)
          super
          subclass.annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true,
                               open_world_hint: true)
        end

        def call(server_context:, **arguments)
          text(execute(server_context[:runtime], **defaults.merge(arguments)))
        rescue ObservabilityMcp::Error => e
          text(e.message, error: true)
        rescue StandardError => e
          warn "[observability-mcp] #{tool_name} failed: #{e.class}: #{e.message}\n  #{e.backtrace&.first(8)&.join("\n  ")}"
          text("Unexpected #{e.class} in #{tool_name} (a server bug; details on the MCP server's stderr). " \
               'Retry with different arguments or a narrower query.', error: true)
        end

        def defaults
          @defaults ||= input_schema.to_h.fetch(:properties, {}).filter_map do |name, property|
            [name.to_sym, property[:default]] if property.key?(:default)
          end.to_h
        end

        private

        def text(content, error: false) = MCP::Tool::Response.new([{ type: 'text', text: content }], error: error)

        def time_range(since:, from:, to:) = TimeRange.parse(since: since, from: from, to: to)

        def search(runtime, target, query, type:, stream: nil)
          request = -> { target.client.search(target.org, query.to_h, type: type) }
          stream ? runtime.with_stream_suggestions(target, stream, type: type, &request) : request.call
        end

        def empty_result(target, time_range, subject)
          "No #{subject} in #{target.label} for window #{time_range}. " \
            'Widen `since`, relax the filters, or check names with list_streams/describe_stream.'
        end
      end
    end
  end
end
