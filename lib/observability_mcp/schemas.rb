# frozen_string_literal: true

module ObservabilityMcp
  # Tool input schemas, written with the Schematist DSL. The MCP SDK validates every tool call
  # against them (json_schemer, JSON Schema 2020-12) before the tool runs, and the descriptions are
  # what the model reads to choose argument values — so keep them precise.
  module Schemas
    # MCP input schema hash for a Schematist schema class. `title` is dropped: the tool name already says it.
    def self.input(schema_class) = schema_class.new.to_json_schema.reject { |key, _| key.to_s == 'title' }
  end
end

require_relative 'schemas/common'
require_relative 'schemas/list_environments'
require_relative 'schemas/list_streams'
require_relative 'schemas/describe_stream'
require_relative 'schemas/search_logs'
require_relative 'schemas/run_sql'
require_relative 'schemas/field_values'
require_relative 'schemas/search_traces'
require_relative 'schemas/get_trace'
require_relative 'schemas/query_metrics'
