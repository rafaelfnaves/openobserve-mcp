# frozen_string_literal: true

require 'test_helper'

class SearchQueryTest < Minitest::Test
  SearchQuery = ObservabilityMcp::SearchQuery

  def test_quotes_identifiers_and_literals
    assert_equal '"my-stream"', SearchQuery.ident('my-stream')
    assert_equal '"a""b"', SearchQuery.ident('a"b')
    assert_equal "'it''s'", SearchQuery.literal("it's")
  end

  def test_select_builds_a_bounded_query
    sql = SearchQuery.select(stream: 'log_workers', columns: ['"body"'], where: ["severity = 'ERROR'", nil, ' '],
                             limit: 20)

    assert_equal %(SELECT "body" FROM "log_workers" WHERE (severity = 'ERROR') ORDER BY _timestamp DESC LIMIT 20), sql
  end

  def test_normalize_quotes_only_names_that_need_it_outside_literals_and_quoted_identifiers
    sql = SearchQuery.normalize("SELECT \"a from b\" FROM log-app JOIN other ON x = y WHERE body LIKE '%from x-y%'", limit: 5)

    assert_equal %(SELECT "a from b" FROM "log-app" JOIN other ON x = y WHERE body LIKE '%from x-y%' LIMIT 5), sql
  end

  def test_normalize_leaves_functions_keywords_and_case_alone
    {
      'SELECT * FROM unnest(arr)' => 'SELECT * FROM unnest(arr) LIMIT 5',
      'SELECT * FROM a JOIN LATERAL x ON true' => 'SELECT * FROM a JOIN LATERAL x ON true LIMIT 5',
      'SELECT EXTRACT(year FROM ts) FROM Log_App' => 'SELECT EXTRACT(year FROM ts) FROM Log_App LIMIT 5'
    }.each { |input, expected| assert_equal expected, SearchQuery.normalize(input, limit: 5) }
  end

  def test_normalize_drops_comments_so_the_limit_stays_effective
    assert_equal 'SELECT * FROM t LIMIT 5', SearchQuery.normalize("-- why\nSELECT * FROM t -- note", limit: 5)
    assert_equal 'SELECT * FROM t   LIMIT 5', SearchQuery.normalize('SELECT * FROM t /* x */ LIMIT 9;', limit: 5)
  end

  def test_normalize_caps_an_existing_limit
    assert_equal 'SELECT * FROM "default" LIMIT 3', SearchQuery.normalize('SELECT * FROM "default" LIMIT 3;', limit: 50)
    assert_equal 'SELECT * FROM t LIMIT 50', SearchQuery.normalize('SELECT * FROM t LIMIT 1000', limit: 50)
    assert_equal 'SELECT * FROM t LIMIT 50 OFFSET 10', SearchQuery.normalize('SELECT * FROM t LIMIT 1000 OFFSET 10', limit: 50)
  end

  def test_normalize_only_allows_one_read_statement
    ['DELETE FROM default', 'SELECT 1 FROM a; DROP TABLE a', 'SELECT 1'].each do |sql|
      assert_raises(ObservabilityMcp::Error, sql) { SearchQuery.normalize(sql, limit: 1) }
    end
    assert_includes SearchQuery.normalize("SELECT * FROM a WHERE b = 'x;y'", limit: 1), "'x;y'"
    assert_includes SearchQuery.normalize('SELECT "a;b" FROM a', limit: 1), '"a;b"'
  end

  def test_body_carries_the_microsecond_window
    range = ObservabilityMcp::TimeRange.new(1_000_000, 2_000_000)
    body = SearchQuery.new('SELECT 1', time_range: range, size: 10).to_h

    assert_equal({ query: { sql: 'SELECT 1', start_time: 1_000_000, end_time: 2_000_000, from: 0, size: 10 } }, body)
  end
end
