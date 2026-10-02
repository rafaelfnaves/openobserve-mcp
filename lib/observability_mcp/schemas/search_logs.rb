# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class SearchLogs < Schematist::Schema
      extend Common

      target_params
      stream_param
      stream_type_param
      string :text, required: false,
                    description: "Full-text search over the stream's full-text fields (match_all), e.g. \"timeout\"."
      where_param
      array :fields, of: :string, required: false,
                     description: 'Only return these fields (_timestamp is always included). Default: all non-empty fields.'
      time_window_params(default: '1h')
      limit_param(default: 20, maximum: 200)
      string :order, required: false, enum: %w[desc asc], default: 'desc', description: 'Sort by _timestamp.'
      max_chars_param
    end
  end
end
