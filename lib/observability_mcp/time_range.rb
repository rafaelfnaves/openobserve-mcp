# frozen_string_literal: true

module ObservabilityMcp
  # A search window in Unix microseconds — the unit OpenObserve's _search API requires.
  #
  # Accepts relative durations ("15m", "2h ago", "7d"), ISO8601 timestamps and epochs in any precision.
  # Parsing is strict on purpose: anything ambiguous is rejected instead of silently producing a wrong
  # window. Epoch precision is inferred from the digit count (a 19-digit nanosecond value is fine), and
  # timestamps without an offset are UTC — never the server's local zone.
  class TimeRange
    USEC = 1_000_000
    DURATION = /\A(\d+)\s*(s|m|h|d|w)(?:\s+ago)?\z/i
    TIMESTAMP = /\A(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}(?:\.\d+)?))?)?\s*(Z|[+-]\d{2}:?\d{2})?\z/i
    UNIT_SECONDS = { 's' => 1, 'm' => 60, 'h' => 3_600, 'd' => 86_400, 'w' => 604_800 }.freeze
    MAX_SECONDS = 31 * 86_400
    FORMAT_HINT = "Use ISO8601 (2026-10-01T12:00:00Z; no offset = UTC), a Unix epoch, or a relative duration like '30m', '2h', '7d'."

    attr_reader :start_us, :end_us

    # since: relative window ending at `to` (or now). from/to: absolute bounds; `from` wins over `since`.
    def self.parse(since: nil, from: nil, to: nil, default: '1h', now: Time.now)
      now_us = (now.to_r * USEC).to_i
      end_us = to ? to_us(to, now_us) : now_us
      start_us = from ? to_us(from, now_us) : end_us - duration_us(since || default)
      new(start_us, end_us)
    end

    def self.duration_us(value)
      match = DURATION.match(value.to_s.strip)
      raise Error, "Invalid duration '#{value}'. Use forms like '30m', '2h', '7d'." unless match

      match[1].to_i * UNIT_SECONDS.fetch(match[2].downcase) * USEC
    end

    def self.to_us(value, now_us)
      text = value.to_s.strip
      case text
      when /\A\d+\z/ then epoch_to_us(text)
      when DURATION then now_us - duration_us(text)
      when /\Anow\z/i then now_us
      when TIMESTAMP then (timestamp(Regexp.last_match).to_r * USEC).to_i
      else raise ArgumentError
      end
    rescue ArgumentError
      raise Error, "Invalid time '#{value}'. #{FORMAT_HINT}"
    end

    def self.timestamp(match)
      year, month, day, hour, minute, second, zone = match.captures
      zone = case zone
             when nil, /\Az\z/i then 'UTC'
             else zone.sub(/(\d{2}):?(\d{2})\z/, '\\1:\\2')
             end
      Time.new(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, Rational(second || '0'), zone)
    end
    private_class_method :timestamp

    def self.epoch_to_us(digits)
      value = digits.to_i
      case digits.length
      when ..10 then value * USEC
      when 11..13 then value * 1_000
      when 14..16 then value
      else value / 1_000
      end
    end

    def self.format_us(us) = Time.at(Rational(us, USEC)).utc.iso8601(3)

    def initialize(start_us, end_us)
      raise Error, "Time window start (#{self.class.format_us(start_us)}) must be before its end " \
                   "(#{self.class.format_us(end_us)})." unless start_us < end_us
      if end_us - start_us > MAX_SECONDS * USEC
        raise Error, "Time window of #{humanize(end_us - start_us)} is too large (max #{MAX_SECONDS / 86_400}d). Narrow it."
      end

      @start_us = start_us
      @end_us = end_us
    end

    def seconds = (end_us - start_us) / USEC

    def to_s = "#{self.class.format_us(start_us)} → #{self.class.format_us(end_us)} (#{humanize(end_us - start_us)})"

    private

    def humanize(us)
      seconds = us / USEC
      UNIT_SECONDS.reverse_each do |unit, size|
        return "#{(seconds.to_f / size).round(1).to_s.delete_suffix('.0')}#{unit}" if seconds >= size
      end
      "#{seconds}s"
    end
  end
end
