# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class QueryMetrics < Schematist::Schema
      extend Common

      target_params
      string :promql, description: 'PromQL expression, e.g. sum by (faas_name) (rate(faas_invocations[5m])). ' \
                                   'Metric names are the metrics streams from list_streams.'
      time_window_params(default: '1h')
      string :step, required: false,
                    description: 'Range query resolution, e.g. 30s, 5m, 1h. Default: about 60 points over the window.'
      boolean :instant, required: false, default: false,
                        description: 'Evaluate once at `to` (or now) instead of over the window.'
      limit_param(default: 20, maximum: 100, description: 'Max series returned (highest max value first).')
    end
  end
end
