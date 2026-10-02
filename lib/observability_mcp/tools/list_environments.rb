# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class ListEnvironments < Base
      tool_name 'list_environments'
      description 'List the configured OpenObserve environments, their organizations and the defaults. ' \
                  'Use first when unsure which env/org to query.'
      input_schema Schemas.input(Schemas::ListEnvironments)

      def self.execute(runtime, check_orgs:)
        config = runtime.config
        return 'No environments configured. Set OO_<ENV>_URL, OO_<ENV>_USER and OO_<ENV>_PASSWORD.' if config.environments.empty?

        lines = config.environments.values.map { environment_line(runtime, it, check_orgs) }
        lines << "defaults: env=#{config.default_env || '(none)'} org=#{config.default_org || '(per env or none)'}"
        lines.join("\n")
      end

      def self.environment_line(runtime, environment, check_orgs)
        parts = ["- #{environment.name}", "host=#{environment.host}"]
        parts << "default_org=#{environment.default_org}" if environment.default_org
        if !environment.ready?
          parts << "NOT USABLE (#{environment.problems.join('; ')})"
        elsif check_orgs
          parts << "orgs: #{organizations(runtime, environment)}"
        end
        parts.join(' · ')
      end

      def self.organizations(runtime, environment)
        runtime.organizations(environment).join(', ')
      rescue ApiError => e
        "unavailable (#{e.message})"
      end
      private_class_method :environment_line, :organizations
    end
  end
end
