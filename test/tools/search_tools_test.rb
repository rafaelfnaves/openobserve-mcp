# frozen_string_literal: true

require 'test_helper'

class SearchToolsTest < Minitest::Test
  TS = 1_790_856_000_000_000

  def test_search_logs_builds_the_query_and_window
    stub_search([{ '_timestamp' => TS, 'body' => 'boom', 'level' => 'error' }])

    text, error = call_tool('search_logs', { stream: 'app-logs', text: "can't", where: "level = 'error'",
                                             fields: %w[body level], since: '2h', limit: 5 })

    refute error
    assert_requested(:post, "#{API}/_search", query: { type: 'logs' }) do |request|
      query = JSON.parse(request.body)['query']
      assert_equal %(SELECT "_timestamp", "body", "level" FROM "app-logs" WHERE (level = 'error') AND (match_all('can''t')) ) +
                   'ORDER BY _timestamp DESC LIMIT 5', query['sql']
      assert_equal 7_200_000_000, query['end_time'] - query['start_time']
      assert_equal 5, query['size']
    end
    assert_match(%r{\Astaging/serverless app-logs \(logs\) · 1 of 1 rows · 12ms · window .* \(2h\)\nsql: SELECT}, text)
    assert text.end_with?("_timestamp | body | level\n2026-10-01T12:00:00.000Z | boom | error")
  end

  def test_search_logs_reports_empty_windows
    stub_search([])

    text, error = call_tool('search_logs', { stream: 'app' })

    refute error
    assert_match(/\ANo records in staging\/serverless for window .* \(1h\)\. Widen `since`/, text)
  end

  def test_run_sql_normalizes_and_rejects_writes
    stub_search([{ 'n' => 3 }], type: 'traces')

    text, = call_tool('run_sql', { sql: 'SELECT count(*) AS n FROM default', type: 'traces' })
    assert_includes text, 'sql (normalized): SELECT count(*) AS n FROM default LIMIT 50'
    assert text.end_with?("n\n3")

    text, error = call_tool('run_sql', { sql: 'DROP TABLE default' })
    assert error
    assert_equal 'Only a single SELECT or WITH statement is allowed.', text
  end

  def test_field_values_lists_counts
    stub_search([{ 'value' => 'INFO', 'count' => 4070 }, { 'value' => nil, 'count' => 9 }])

    text, = call_tool('field_values', { stream: 'default', field: 'severity', where: "service_name = 'api'" })

    assert_requested(:post, "#{API}/_search", query: { type: 'logs' }) do |request|
      assert_equal %(SELECT "severity" AS "value", count(*) AS "count" FROM "default" WHERE (service_name = 'api') ) +
                   'GROUP BY "severity" ORDER BY "count" DESC LIMIT 20', JSON.parse(request.body).dig('query', 'sql')
    end
    assert text.end_with?("4,070  INFO\n    9  (null)")
  end
end
