# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class SearchTraces < Schematist::Schema
      extend Common

      target_params
      string :stream, required: false, default: 'default', description: 'Traces stream name.'
      string :service, required: false, description: 'Exact service_name of any span in the trace.'
      string :operation, required: false, description: 'Exact operation_name of any span in the trace.'
      boolean :errors_only, required: false, default: false, description: 'Only traces with at least one ERROR span.'
      number :min_duration_ms, required: false, minimum: 0, description: 'Only traces having a span at least this long.'
      where_param
      time_window_params(default: '1h')
      limit_param(default: 20, maximum: 100, description: 'Max traces returned (most recent first).')
    end
  end
end
