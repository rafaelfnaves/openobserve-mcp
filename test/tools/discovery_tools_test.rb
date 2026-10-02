# frozen_string_literal: true

require 'test_helper'

class DiscoveryToolsTest < Minitest::Test
  def test_list_environments_shows_orgs_and_missing_configuration
    stub_request(:get, 'https://oo.test/api/organizations').to_return(json_response({ 'data' => [{ 'identifier' => 'serverless' }] }))
    runtime = build_runtime(ENV_VARS.merge('OO_PROD_URL' => 'https://prod.test'))

    text, error = call_tool('list_environments', {}, runtime: runtime)

    refute error
    assert_equal <<~TEXT.chomp, text
      - prod · host=prod.test · NOT USABLE (missing OO_PROD_USER, OO_PROD_PASSWORD)
      - staging · host=oo.test · default_org=serverless · orgs: serverless
      defaults: env=(none) org=(per env or none)
    TEXT
  end

  def test_list_streams_groups_by_type_and_collapses_metric_families
    streams = [
      { 'name' => 'default', 'stream_type' => 'logs', 'stats' => { 'doc_num' => 1500, 'doc_time_max' => 1_790_856_000_000_000 } },
      { 'name' => 'distinct_values', 'stream_type' => 'metadata', 'stats' => {} },
      *%w[faas_duration faas_duration_bucket faas_duration_count faas_invocations].map { { 'name' => it, 'stream_type' => 'metrics', 'stats' => {} } }
    ]
    stub_request(:get, "#{API}/streams").to_return(json_response({ 'list' => streams }))

    text, = call_tool('list_streams')

    assert_equal <<~TEXT.chomp, text
      staging/serverless · 5 streams
      logs:
        default · 1,500 docs · last 2026-10-01T12:00:00.000Z
      metrics:
        faas_duration (+_bucket _count)
        faas_invocations
    TEXT
  end

  def test_describe_stream_groups_fields_by_type
    schema = { 'schema' => [{ 'name' => 'body', 'type' => 'Utf8' }, { 'name' => '_timestamp', 'type' => 'Int64' },
                            { 'name' => 'level', 'type' => 'Utf8' }],
               'stats' => { 'doc_num' => 10 }, 'settings' => { 'full_text_search_keys' => ['body'] } }
    stub_request(:get, "#{API}/streams/app/schema").with(query: { type: 'logs' }).to_return(json_response(schema))

    text, = call_tool('describe_stream', { stream: 'app' })

    assert_equal <<~TEXT.chomp, text
      staging/serverless app (logs) · 3 fields · 10 docs
      full-text fields (used by search_logs text): body
      Utf8 (2): body, level
      Int64 (1): _timestamp
    TEXT
  end

  def test_unknown_stream_suggests_close_names
    stub_request(:get, "#{API}/streams/log_aplication/schema").with(query: { type: 'logs' })
                                                               .to_return(json_response({ 'code' => 404, 'message' => 'stream not found' }, status: 404))
    stub_request(:get, "#{API}/streams").with(query: { type: 'logs' })
                                        .to_return(json_response({ 'list' => [{ 'name' => 'log_application' }, { 'name' => 'log_workers' }] }))

    text, error = call_tool('describe_stream', { stream: 'log_aplication' })

    assert error
    assert_equal "Stream 'log_aplication' (logs) not found in staging/serverless. Did you mean: log_application?", text
  end

  def test_schema_validation_and_configuration_errors_reach_the_agent
    text, error = call_tool('search_logs', { stream: 'x', limit: 5_000 })
    assert error
    assert_match(/limit.*200/, text)

    text, error = call_tool('list_streams', { env: 'qa' })
    assert error
    assert_equal "Unknown env 'qa'. Configured environments: staging.", text
  end
end
