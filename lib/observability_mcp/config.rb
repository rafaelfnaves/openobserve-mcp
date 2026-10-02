# frozen_string_literal: true

require 'uri'

module ObservabilityMcp
  # Reads OpenObserve environments from ENV, using the same convention as oo-cli:
  #
  #   OO_<ENV>_URL, OO_<ENV>_USER, OO_<ENV>_PASSWORD  (required per environment; <ENV> may contain "_")
  #   OO_<ENV>_ORG                                    (optional default org for that environment)
  #   OO_DEFAULT_ENV, OO_DEFAULT_ORG, OO_TIMEOUT      (optional)
  #   OO_ALLOW_INSECURE_HTTP=true                     (optional; permit http:// URLs to non-local hosts)
  class Config
    LOCAL_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze

    Environment = Data.define(:name, :url, :user, :password, :default_org, :allow_http) do
      def missing_vars
        { 'URL' => url, 'USER' => user, 'PASSWORD' => password }
          .select { |_, value| value.to_s.empty? }
          .map { |suffix, _| "OO_#{name.upcase}_#{suffix}" }
      end

      # Everything that prevents using this environment, as human-readable sentences.
      def problems
        missing = missing_vars
        return ["missing #{missing.join(', ')}"] if missing.any?

        uri = URI(url)
        return ["OO_#{name.upcase}_URL must be an absolute http(s) URL"] unless uri.is_a?(URI::HTTP) && uri.host
        if uri.scheme == 'http' && !allow_http && !LOCAL_HOSTS.include?(uri.host)
          return ["OO_#{name.upcase}_URL uses plain http, which would send credentials unencrypted " \
                  '(use https, or set OO_ALLOW_INSECURE_HTTP=true)']
        end

        []
      rescue URI::InvalidURIError
        ["OO_#{name.upcase}_URL is not a valid URL"]
      end

      def ready? = problems.empty?

      def host
        URI(url).host || url
      rescue URI::InvalidURIError
        url
      end

      # Never expose the password through inspect/pp (logs, exception reporters, debugging).
      def inspect = "#<#{self.class.name} #{name} url=#{url} user=#{user} password=[REDACTED]>"
      alias_method :to_s, :inspect

      def pretty_print(printer) = printer.text(inspect)
    end

    URL_VAR = /\AOO_([A-Z0-9_]+)_URL\z/
    RESERVED_PREFIXES = %w[DEFAULT].freeze
    DEFAULT_TIMEOUT = 30.0

    attr_reader :environments, :default_env, :default_org, :timeout

    def self.from_env(env = ENV) = new(env)

    def initialize(env = ENV)
      @environments = discover(env)
      @default_env = presence(env['OO_DEFAULT_ENV'])&.downcase || (environments.keys.first if environments.one?)
      @default_org = presence(env['OO_DEFAULT_ORG'])
      @timeout = parse_timeout(env['OO_TIMEOUT'])
    end

    def environment(name = nil)
      name = presence(name)&.downcase || default_env
      raise Error, "Parameter `env` is required. Configured environments: #{environment_names}." unless name

      environment = environments.fetch(name) do
        raise Error, "Unknown env '#{name}'. Configured environments: #{environment_names}."
      end
      return environment if environment.ready?

      raise Error, "Env '#{name}' is not usable: #{environment.problems.join('; ')}."
    end

    def org(environment, name = nil)
      presence(name) || environment.default_org || default_org ||
        raise(Error, "Parameter `org` is required for env '#{environment.name}' " \
                     "(or set OO_#{environment.name.upcase}_ORG / OO_DEFAULT_ORG). " \
                     'Call list_environments to see the available orgs.')
    end

    private

    def discover(env)
      allow_http = env['OO_ALLOW_INSECURE_HTTP'].to_s.strip.downcase == 'true'
      env.keys
         .filter_map { it[URL_VAR, 1] }
         .reject { RESERVED_PREFIXES.include?(it) }
         .sort
         .to_h do |prefix|
           environment = Environment.new(
             name: prefix.downcase,
             url: env["OO_#{prefix}_URL"].to_s.strip.chomp('/'),
             user: presence(env["OO_#{prefix}_USER"]),
             password: presence(env["OO_#{prefix}_PASSWORD"]),
             default_org: presence(env["OO_#{prefix}_ORG"]),
             allow_http: allow_http
           )
           [environment.name, environment]
         end
    end

    # Accepts "30" or "30s"; anything else falls back to the default with a warning instead of
    # killing the server at boot.
    def parse_timeout(value)
      return DEFAULT_TIMEOUT if presence(value).nil?

      seconds = Float(value.to_s.strip.delete_suffix('s'), exception: false)
      return seconds if seconds&.positive?

      warn "[observability-mcp] ignoring invalid OO_TIMEOUT=#{value.inspect}; using #{DEFAULT_TIMEOUT.to_i}s"
      DEFAULT_TIMEOUT
    end

    def environment_names
      environments.empty? ? 'none (set OO_<ENV>_URL/USER/PASSWORD)' : environments.keys.join(', ')
    end

    def presence(value)
      value = value.to_s.strip
      value.empty? ? nil : value
    end
  end
end
