# frozen_string_literal: true

require 'test_helper'

class TimeRangeTest < Minitest::Test
  TimeRange = ObservabilityMcp::TimeRange
  NOW = Time.utc(2026, 10, 1, 12, 0, 0)
  NOW_US = 1_790_856_000_000_000

  def test_defaults_to_the_last_hour_in_microseconds
    range = TimeRange.parse(now: NOW)

    assert_equal NOW_US, range.end_us
    assert_equal NOW_US - 3_600_000_000, range.start_us
    assert_equal 16, range.start_us.to_s.length
  end

  def test_since_accepts_relative_durations
    assert_equal 7 * 86_400 * 1_000_000, TimeRange.parse(since: '7d', now: NOW).then { it.end_us - it.start_us }
    assert_equal 15 * 60 * 1_000_000, TimeRange.parse(since: '15m', now: NOW).then { it.end_us - it.start_us }
  end

  def test_infers_epoch_precision_from_digit_count
    expected = NOW_US - 3_600_000_000
    %w[1790852400 1790852400000 1790852400000000 1790852400000000000].each do |epoch|
      assert_equal expected, TimeRange.parse(from: epoch, now: NOW).start_us, "epoch #{epoch}"
    end
  end

  def test_from_and_to_accept_iso8601_and_relative_values
    range = TimeRange.parse(from: '2026-10-01T09:00:00Z', to: '2h', now: NOW)

    assert_equal '2026-10-01T09:00:00.000Z', TimeRange.format_us(range.start_us)
    assert_equal '2026-10-01T10:00:00.000Z', TimeRange.format_us(range.end_us)
    assert_equal '2026-10-01T09:00:00.000Z → 2026-10-01T10:00:00.000Z (1h)', range.to_s
  end

  def test_timestamps_without_offset_are_utc_regardless_of_the_server_zone
    with_timezone('America/Sao_Paulo') do
      %w[2026-10-01T09:00 2026-10-01T09:00:00].push('2026-10-01 09:00').each do |input|
        assert_equal '2026-10-01T09:00:00.000Z', TimeRange.format_us(TimeRange.parse(from: input, now: NOW).start_us), input
      end
      assert_equal '2026-10-01T12:00:00.500Z', TimeRange.format_us(TimeRange.to_us('2026-10-01T09:00:00.5-03:00', NOW_US))
    end
  end

  def test_accepts_relative_ago
    assert_equal NOW_US - 7_200_000_000, TimeRange.parse(from: '2h ago', now: NOW).start_us
  end

  def test_rejects_ambiguous_or_invalid_values
    ['yesterday-ish', '1h ago x', '1.5h', '10:00', '1e10', '2026-13-01', '-5'].each do |input|
      error = assert_raises(ObservabilityMcp::Error, input) { TimeRange.parse(from: input, now: NOW) }
      assert_match(/Invalid time/, error.message)
    end
    assert_raises(ObservabilityMcp::Error) { TimeRange.parse(since: '1 hour', now: NOW) }
  end

  def with_timezone(zone)
    original = ENV['TZ']
    ENV['TZ'] = zone
    yield
  ensure
    ENV['TZ'] = original
  end

  def test_rejects_inverted_and_oversized_windows
    assert_raises(ObservabilityMcp::Error) { TimeRange.parse(from: '1h', to: '2h', now: NOW) }
    error = assert_raises(ObservabilityMcp::Error) { TimeRange.parse(since: '60d', now: NOW) }
    assert_match(/too large/, error.message)
  end
end
