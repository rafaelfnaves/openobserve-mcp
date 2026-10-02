# frozen_string_literal: true

require 'test_helper'

class ClientTest < Minitest::Test
  def client = ObservabilityMcp::Client.new(ObservabilityMcp::Config.new(ENV_VARS).environment, timeout: 5)

  def test_sends_basic_auth_and_encodes_path_segments
    stub_request(:get, 'https://oo.test/api/serverless/streams/my%20stream/schema')
      .with(query: { type: 'logs' }, basic_auth: %w[user secret])
      .to_return(json_response({ 'name' => 'my stream' }))

    assert_equal({ 'name' => 'my stream' }, client.stream_schema('serverless', 'my stream', type: 'logs'))
  end

  def test_errors_are_short_and_actionable
    stub_request(:post, "#{API}/_search").with(query: { type: 'logs' }).to_return(json_response(
      { 'code' => 20_004, 'message' => 'Search field not found: No field named nope. Valid fields are a, b, c' }, status: 400
    ))

    error = assert_raises(ObservabilityMcp::ApiError) { client.search('serverless', {}, type: 'logs') }
    assert_equal 'OpenObserve staging returned HTTP 400: Search field not found: No field named nope. ' \
                 'Call describe_stream to see valid field names.', error.message
  end

  def test_includes_error_detail_behind_generic_messages
    stub_request(:post, "#{API}/_search").with(query: { type: 'logs' }).to_return(json_response(
      { 'code' => 20_008, 'message' => 'Search SQL execute error',
        'error_detail' => 'Schema error: No field named nope. Valid fields are a, b' }, status: 400
    ))

    error = assert_raises(ObservabilityMcp::ApiError) { client.search('serverless', {}, type: 'logs') }
    assert_equal 'OpenObserve staging returned HTTP 400: Search SQL execute error: Schema error: No field named nope. ' \
                 'Call describe_stream to see valid field names.', error.message
  end

  def test_unauthorized_points_at_the_credentials_without_leaking_them
    stub_request(:get, "#{API}/streams").to_return(status: 401, body: 'Unauthorized Access')

    error = assert_raises(ObservabilityMcp::ApiError) { client.streams('serverless') }
    assert_match(/HTTP 401: Unauthorized Access Check OO_STAGING_USER/, error.message)
    refute_includes error.message, 'secret'
  end

  def test_timeouts_suggest_narrowing_the_query
    stub_request(:get, "#{API}/streams").to_timeout

    assert_match(/did not answer within 5s/, assert_raises(ObservabilityMcp::ApiError) { client.streams('serverless') }.message)
  end

  def test_non_json_success_is_an_error
    stub_request(:get, "#{API}/streams").to_return(status: 200, body: '<html>')

    assert_match(/non-JSON/, assert_raises(ObservabilityMcp::ApiError) { client.streams('serverless') }.message)
  end
end
