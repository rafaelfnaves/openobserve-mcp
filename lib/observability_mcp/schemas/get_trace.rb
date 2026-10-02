# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class GetTrace < Schematist::Schema
      extend Common

      target_params
      string :trace_id, pattern: '^[0-9a-fA-F]{16,32}$', description: 'Hex trace id (from logs or search_traces).'
      string :stream, required: false, default: 'default', description: 'Traces stream name.'
      time_window_params(default: '24h')
      integer :max_spans, required: false, minimum: 1, maximum: 2_000, default: 300,
                          description: 'Max spans fetched (earliest first).'
      boolean :show_attributes, required: false, default: false,
                                description: 'Show every span attribute instead of only the key ones (http, db, rpc, ...).'
      max_chars_param(default: 200)
    end
  end
end
