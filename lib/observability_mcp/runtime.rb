# frozen_string_literal: true

module ObservabilityMcp
  # Everything a tool needs at call time: configuration, cached metadata and one client per environment.
  # Passed to tools through the MCP server_context as `server_context[:runtime]`.
  class Runtime
    # The resolved env/org pair a tool call works against.
    Target = Data.define(:environment, :org, :client) do
      def label = "#{environment.name}/#{org}"
    end

    attr_reader :config, :cache

    def initialize(config: Config.from_env, cache: Cache.new)
      @config = config
      @cache = cache
      @clients = {}
    end

    def target(env: nil, org: nil)
      environment = config.environment(env)
      Target.new(environment: environment, org: config.org(environment, org), client: client(environment))
    end

    def client(environment)
      @clients[environment.name] ||= Client.new(environment, timeout: config.timeout)
    end

    def streams(target, type: nil)
      cache.fetch([:streams, target.label, type]) do
        target.client.streams(target.org, type: type).fetch('list', [])
      end
    end

    def stream_schema(target, stream, type:)
      cache.fetch([:schema, target.label, stream, type]) do
        target.client.stream_schema(target.org, stream, type: type)
      end
    end

    def organizations(environment)
      cache.fetch([:organizations, environment.name]) do
        client(environment).organizations.fetch('data', []).map { it['identifier'] || it['name'] }
      end
    end

    # Runs the block and, when OpenObserve says the stream does not exist, re-raises with the
    # closest stream names so the agent can retry without another discovery round-trip.
    def with_stream_suggestions(target, stream, type:)
      yield
    rescue ApiError => e
      raise unless e.stream_not_found?

      names = streams(target, type: type).map { it['name'] }.uniq
      raise Error, "Stream '#{stream}' (#{type}) not found in #{target.label}. #{suggest(stream, names)}"
    end

    private

    def suggest(stream, names)
      return 'This org has no streams of that type.' if names.empty?

      close = DidYouMean::SpellChecker.new(dictionary: names).correct(stream)
      close |= names.select { it.include?(stream) || stream.include?(it) }
      if close.any?
        "Did you mean: #{close.first(5).join(', ')}?"
      else
        "Available: #{names.first(15).join(', ')}#{names.size > 15 ? ', …' : ''}"
      end
    end
  end
end
