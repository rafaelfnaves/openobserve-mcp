# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class FieldValues < Schematist::Schema
      extend Common

      target_params
      stream_param
      string :field, description: 'Field to count distinct values of, e.g. service_name, severity, http_status_code.'
      stream_type_param
      where_param
      time_window_params(default: '1h')
      limit_param(default: 20, maximum: 100, description: 'Max distinct values returned (most frequent first).')
    end
  end
end
