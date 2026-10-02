# frozen_string_literal: true

require_relative 'tools/base'
require_relative 'tools/list_environments'
require_relative 'tools/list_streams'
require_relative 'tools/describe_stream'
require_relative 'tools/search_logs'
require_relative 'tools/run_sql'
require_relative 'tools/field_values'
require_relative 'tools/search_traces'
require_relative 'tools/get_trace'
require_relative 'tools/query_metrics'

module ObservabilityMcp
  module Tools
    ALL = [
      ListEnvironments, ListStreams, DescribeStream, SearchLogs, RunSql, FieldValues, SearchTraces, GetTrace, QueryMetrics
    ].freeze
  end
end
