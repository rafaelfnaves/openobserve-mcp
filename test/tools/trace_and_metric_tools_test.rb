# frozen_string_literal: true

require 'test_helper'

class TraceAndMetricToolsTest < Minitest::Test
  def test_search_traces_sends_filters_and_summarizes_traces
    trace = { 'trace_id' => 'abc', 'start_time' => 1_790_856_000_000_000_000, 'duration' => 1_500_000, 'spans' => [3, 1],
              'service_name' => [{ 'service_name' => 'api', 'count' => 3 }],
              'first_event' => { 'service_name' => 'api', 'operation_name' => 'GET /cars' } }
    stub_request(:get, "#{API}/default/traces/latest").with(query: hash_including({}))
                                                      .to_return(json_response({ 'hits' => [trace], 'total' => 7 }))

    text, = call_tool('search_traces', { service: 'api', errors_only: true, min_duration_ms: 250 })

    assert_requested(:get, "#{API}/default/traces/latest",
                     query: hash_including('filter' => "(service_name = 'api') AND (span_status = 'ERROR') AND (duration >= 250000)",
                                           'size' => '20'))
    assert_equal '2026-10-01T12:00:00.000Z · 1.5s · 3 spans · ✗ 1 errors · api(3) · root=GET /cars · trace_id=abc',
                 text.lines.last
  end

  def test_get_trace_queries_spans_by_trace_id
    span = { 'trace_id' => 'abcdef0123456789', 'span_id' => 's1', 'service_name' => 'api', 'operation_name' => 'GET /',
             'start_time' => 1_790_856_000_000_000_000, 'end_time' => 1_790_856_000_005_000_000, 'duration' => 5_000 }
    stub_search([span], type: 'traces')

    text, = call_tool('get_trace', { trace_id: 'ABCDEF0123456789', max_spans: 10 })

    assert_requested(:post, "#{API}/_search", query: { type: 'traces' }) do |request|
      query = JSON.parse(request.body)['query']
      assert_equal %(SELECT * FROM "default" WHERE (trace_id = 'abcdef0123456789') ORDER BY start_time ASC LIMIT 11), query['sql']
      assert_equal 86_400_000_000, query['end_time'] - query['start_time']
    end
    assert_equal '└─ [api] GET / 5.0ms @+0.0ms', text.lines.last

    _, error = call_tool('get_trace', { trace_id: 'not-a-trace' })
    assert error
  end

  def test_query_metrics_picks_a_step_and_summarizes
    data = { 'resultType' => 'matrix', 'result' => [{ 'metric' => { 'fn' => 'a' }, 'values' => [[0, '1'], [60, '3']] }] }
    stub_request(:get, "#{API}/prometheus/api/v1/query_range").with(query: hash_including({}))
                                                              .to_return(json_response({ 'status' => 'success', 'data' => data }))

    text, = call_tool('query_metrics', { promql: 'sum(faas_invocations)', since: '6h' })

    assert_requested(:get, "#{API}/prometheus/api/v1/query_range", query: hash_including('step' => '360', 'query' => 'sum(faas_invocations)'))
    assert_match(/step 360s\nmatrix · 1 series · common labels \{fn=a\}\n- \{\} n=2 min=1 avg=2 max=3 last=3 ▁█\z/, text)
  end
end
