# frozen_string_literal: true

module ObservabilityMcp
  # Tiny in-memory TTL cache for metadata that rarely changes (stream lists, schemas, orgs).
  class Cache
    DEFAULT_TTL = 300

    def initialize(ttl: DEFAULT_TTL, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @ttl = ttl
      @clock = clock
      @entries = {}
      @mutex = Mutex.new
    end

    def fetch(key)
      @mutex.synchronize do
        value, expires_at = @entries[key]
        return value if expires_at && expires_at > @clock.call
      end

      yield.tap { |value| @mutex.synchronize { @entries[key] = [value, @clock.call + @ttl] } }
    end
  end
end
