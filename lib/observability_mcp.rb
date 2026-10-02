# frozen_string_literal: true

require 'json'
require 'mcp'
require 'schematist'

module ObservabilityMcp
  VERSION = '0.1.0'

  # Base error for anything the agent can act on. Tools turn it into an error response
  # carrying the message, so messages must be actionable and must never include credentials.
  class Error < StandardError; end
end

require_relative 'observability_mcp/config'
require_relative 'observability_mcp/client'
require_relative 'observability_mcp/cache'
require_relative 'observability_mcp/runtime'
require_relative 'observability_mcp/time_range'
require_relative 'observability_mcp/search_query'
require_relative 'observability_mcp/formatter'
require_relative 'observability_mcp/trace_tree'
require_relative 'observability_mcp/metrics_summary'
require_relative 'observability_mcp/schemas'
require_relative 'observability_mcp/tools'
require_relative 'observability_mcp/server'
