# frozen_string_literal: true

require 'test_helper'

class MetricsSummaryTest < Minitest::Test
  def series(labels, values) = { 'metric' => labels, 'values' => values.each_with_index.map { |v, i| [i * 60, v.to_s] } }

  def test_matrix_prints_common_labels_once_and_stats_per_series
    data = { 'resultType' => 'matrix', 'result' => [
      series({ '__name__' => 'hits', 'fn' => 'a', 'flag' => 'x' }, [1, 2, 3]),
      series({ '__name__' => 'hits', 'fn' => 'b', 'flag' => 'x' }, [5, 'NaN', 9])
    ] }

    assert_equal <<~TEXT.chomp, ObservabilityMcp::MetricsSummary.new(data, limit: 1).render
      matrix · 2 series · common labels {__name__=hits}
      - {fn=b} n=2 min=5 avg=7 max=9 last=9 ▁█
      … 1 more series (filter by label or aggregate, e.g. sum by (label) (...))
    TEXT
  end

  def test_extreme_values_stay_compact
    data = { 'resultType' => 'vector', 'result' => [{ 'metric' => {}, 'value' => [0, '1e300'] }, { 'value' => [0, '0.00001'] }] }

    assert_equal "vector · 2 series\n- {} = 1e+300\n- {} = 1e-05", ObservabilityMcp::MetricsSummary.new(data, limit: 5).render
  end

  def test_vector_and_empty_results
    vector = { 'resultType' => 'vector', 'result' => [{ 'metric' => { 'fn' => 'a' }, 'value' => [0, '2.5'] }] }

    assert_equal "vector · 1 series · common labels {fn=a}\n- {} = 2.5", ObservabilityMcp::MetricsSummary.new(vector, limit: 5).render
    assert_match(/No series matched/, ObservabilityMcp::MetricsSummary.new({ 'resultType' => 'matrix', 'result' => [] }, limit: 5).render)
  end
end
