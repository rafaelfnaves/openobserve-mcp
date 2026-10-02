# frozen_string_literal: true

module ObservabilityMcp
  module Server
    INSTRUCTIONS = <<~TEXT
      Read-only access to OpenObserve logs, traces and metrics. Every tool returns compact text.

      Investigation workflow:
      1. list_environments: which env/org to use (skip when defaults are configured).
      2. list_streams, then describe_stream: real stream and field names. Never guess field names.
      3. field_values: top values of a field (service_name, severity, error_type, http_status_code). Cheapest overview.
      4. search_logs: records with `text`/`where` filters. search_traces: slow or failing traces.
         get_trace: span tree of a trace_id found in logs or search_traces.
      5. run_sql: aggregations (count, GROUP BY, histogram). query_metrics: PromQL over metrics streams.

      Time: pass `since` (15m, 1h, 7d) or `from`/`to` (ISO8601). Never compute epoch values yourself. Output times are UTC.
      Tokens: start with a small `limit` and choose `fields`. Raise `max_chars` only to read a full stack trace.

      Known Cilia streams (confirm with list_streams):
      - prod/cilia-web: logs log_application, log_application_error, log_workers, log_workers_error;
        traces default (Rails requests and Resque workers); system_* host metrics.
      - staging/serverless (only org in staging): traces default (Lambdas), logs default,
        metrics faas_* and gen_ai_client_*.
    TEXT

    module_function

    def build(runtime: Runtime.new)
      MCP::Server.new(
        name: 'openobserve',
        title: 'OpenObserve',
        version: VERSION,
        instructions: INSTRUCTIONS,
        tools: Tools::ALL,
        server_context: { runtime: runtime }
      )
    end
  end
end
