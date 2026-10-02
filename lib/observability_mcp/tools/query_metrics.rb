# frozen_string_literal: true

module ObservabilityMcp
  module Tools
    class QueryMetrics < Base
      POINTS = 60
      MIN_STEP = 15

      tool_name 'query_metrics'
      description 'Run a PromQL query over metrics streams. Returns one line per series with min/avg/max/last and a ' \
                  'sparkline (or the value for instant queries); labels shared by all series are printed once.'
      input_schema Schemas.input(Schemas::QueryMetrics)

      def self.execute(runtime, promql:, since:, instant:, limit:, env: nil, org: nil, from: nil, to: nil, step: nil)
        target = runtime.target(env: env, org: org)
        range = time_range(since: since, from: from, to: to)
        end_s = range.end_us / TimeRange::USEC

        if instant
          header = "#{promql} · #{target.label} · at #{TimeRange.format_us(range.end_us)}"
          response = target.client.prometheus(target.org, 'query', query: promql, time: end_s)
        else
          step_s = step_seconds(step, range)
          header = "#{promql} · #{target.label} · window #{range} · step #{step_s}s"
          response = target.client.prometheus(target.org, 'query_range', query: promql,
                                                                          start: range.start_us / TimeRange::USEC,
                                                                          end: end_s, step: step_s)
        end
        raise Error, "PromQL error: #{response['error'] || response}" unless response['status'] == 'success'

        "#{header}\n#{MetricsSummary.new(response['data'] || {}, limit: limit).render}"
      end

      def self.step_seconds(step, range)
        return [(range.seconds / POINTS.to_f).ceil, MIN_STEP].max unless step
        return step.to_i if step.match?(/\A\d+\z/)

        TimeRange.duration_us(step) / TimeRange::USEC
      end
      private_class_method :step_seconds
    end
  end
end
