# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'observability_mcp'

module TestSupport
  ENV_VARS = {
    'OO_STAGING_URL' => 'https://oo.test/',
    'OO_STAGING_USER' => 'user',
    'OO_STAGING_PASSWORD' => 'secret',
    'OO_STAGING_ORG' => 'serverless'
  }.freeze
  API = 'https://oo.test/api/serverless'

  def build_runtime(env = ENV_VARS)
    ObservabilityMcp::Runtime.new(config: ObservabilityMcp::Config.new(env))
  end

  # Calls a tool through the MCP server (JSON-RPC), so input schema validation is exercised too.
  def call_tool(name, arguments = {}, runtime: build_runtime)
    server = ObservabilityMcp::Server.build(runtime: runtime)
    request = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: name, arguments: arguments } }
    result = JSON.parse(server.handle_json(JSON.generate(request))).fetch('result')
    [result.dig('content', 0, 'text'), result['isError']]
  end

  def json_response(body, status: 200)
    { status: status, body: JSON.generate(body), headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_search(hits, type: 'logs', total: hits.size)
    stub_request(:post, "#{API}/_search").with(query: { type: type })
                                         .to_return(json_response({ 'took' => 12, 'hits' => hits, 'total' => total }))
  end
end

class Minitest::Test
  include TestSupport
end
