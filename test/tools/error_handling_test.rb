# frozen_string_literal: true

require 'test_helper'
require 'open3'

class ErrorHandlingTest < Minitest::Test
  def test_unexpected_exceptions_become_tool_errors_and_are_logged_to_stderr
    ObservabilityMcp::Formatter.stub(:search_header, ->(*) { raise TypeError, 'boom' }) do
      stub_search([{ 'a' => 1 }])
      text, error = nil
      _, stderr = capture_io { text, error = call_tool('search_logs', { stream: 'app' }) }

      assert error
      assert_equal "Unexpected TypeError in search_logs (a server bug; details on the MCP server's stderr). " \
                   'Retry with different arguments or a narrower query.', text
      assert_match(/search_logs failed: TypeError: boom/, stderr)
    end
  end

  def test_schema_defaults_are_applied
    assert_equal({ type: 'logs', since: '1h', limit: 20, order: 'desc', max_chars: 300 }, ObservabilityMcp::Tools::SearchLogs.defaults)
    assert_equal '24h', ObservabilityMcp::Tools::GetTrace.defaults[:since]
  end

  def test_run_sql_truncates_rows_beyond_the_limit
    stub_search((1..5).map { { 'n' => it } })

    text, = call_tool('run_sql', { sql: 'SELECT n FROM t LIMIT 1000', limit: 2 })

    assert_includes text, 'sql (normalized): SELECT n FROM t LIMIT 2'
    assert_includes text, '⚠ 5 rows returned; showing the first 2'
    assert text.end_with?("n\n1\n2")
  end

  def test_list_environments_reports_unreachable_orgs
    stub_request(:get, 'https://oo.test/api/organizations').to_return(status: 503, body: 'down')

    text, error = call_tool('list_environments')

    refute error
    assert_includes text, 'orgs: unavailable (OpenObserve staging returned HTTP 503: down)'
  end

  def test_query_metrics_instant_explicit_step_and_promql_errors
    stub_request(:get, "#{API}/prometheus/api/v1/query").with(query: hash_including({}))
                                                        .to_return(json_response({ 'status' => 'success', 'data' => { 'resultType' => 'scalar', 'result' => [0, '4'] } }))
    stub_request(:get, "#{API}/prometheus/api/v1/query_range").with(query: hash_including('step' => '300'))
                                                              .to_return(json_response({ 'status' => 'error', 'error' => 'bad expr' }))

    text, = call_tool('query_metrics', { promql: 'vector(4)', instant: true })
    assert text.end_with?('scalar = 4 @ 1970-01-01T00:00:00Z')

    text, error = call_tool('query_metrics', { promql: 'x', step: '5m' })
    assert error
    assert_equal 'PromQL error: bad expr', text
  end

  def test_executable_speaks_mcp_over_stdio
    requests = [
      { jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'test', version: '0' } } },
      { jsonrpc: '2.0', method: 'notifications/initialized' },
      { jsonrpc: '2.0', id: 2, method: 'tools/list' }
    ].map { JSON.generate(it) }.join("\n")
    executable = File.expand_path('../../bin/observability-mcp', __dir__)

    stdout, _stderr, status = Open3.capture3(ENV_VARS, executable, stdin_data: "#{requests}\n", chdir: Dir.tmpdir)

    assert status.success?
    responses = stdout.lines.map { JSON.parse(it) }
    assert_equal 'openobserve', responses.first.dig('result', 'serverInfo', 'name')
    assert_equal ObservabilityMcp::Tools::ALL.map(&:tool_name), responses.last.dig('result', 'tools').map { it['name'] }
  end
end
