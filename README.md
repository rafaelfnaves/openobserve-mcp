# observability-mcp

A read-only MCP server for [OpenObserve](https://openobserve.ai/docs/reference/api/) logs, traces and metrics. It is
built on the official [Ruby MCP SDK](https://github.com/modelcontextprotocol/ruby-sdk). The server handles the details that used to go wrong:

- **Time windows**: pass `since: "1h"` or ISO8601 `from`/`to`. The server converts them to the microseconds the API
  requires, and epoch values in any precision are recognized by their digit count. Parsing is strict: a timestamp
  without an offset is UTC, and an ambiguous input such as `1.5h` is rejected rather than turned into a wrong window.
- **SQL details**: stream names are quoted when needed, a `LIMIT` is always enforced, comments are stripped, only read-only statements are allowed, and an
  unknown stream gets a "did you mean" suggestion.
- **Token usage**: output is compact text. Empty values and OpenTelemetry boilerplate are dropped, fields shared by
  every row are printed once, and long values are truncated. Traces render as a call tree and metrics as per-series
  stats with a sparkline. A trace takes about 9× fewer bytes than the raw `_search` JSON.

## Setup

```bash
mise install          # ruby 4.0.6
bundle install
```

Configuration uses the same environment variables as oo-cli:

| Variable | Required | Purpose |
|---|---|---|
| `OO_<ENV>_URL`, `OO_<ENV>_USER`, `OO_<ENV>_PASSWORD` | yes | One environment per `<ENV>` prefix (e.g. `STAGING`, `PROD`, `PROD_EU`). The URL must be https unless the host is localhost |
| `OO_<ENV>_ORG` | no | Default org for that environment (e.g. `OO_STAGING_ORG=serverless`) |
| `OO_DEFAULT_ENV`, `OO_DEFAULT_ORG` | no | Used when a tool call omits `env` / `org` |
| `OO_TIMEOUT` | no | HTTP read timeout in seconds (default 30) |
| `OO_ALLOW_INSECURE_HTTP` | no | Set to `true` to allow plain-http URLs, which send credentials unencrypted |

Register the server with Claude Code. It inherits your shell environment:

```bash
claude mcp add openobserve --scope user -- /path/to/observability-mcp
# If `ruby` on Claude's PATH is not the mise-managed 4.0.6:
claude mcp add openobserve --scope user -- mise exec -C /path/to/observability-mcp -- bin/observability-mcp
```

## Tools

| Tool | What it returns |
|---|---|
| `list_environments` | Configured environments, their orgs (also a credentials check), and the defaults |
| `list_streams` | Streams by type with doc counts and last record time; metric families collapsed |
| `describe_stream` | Fields grouped by type, time range, full-text fields |
| `field_values` | Top values of a field with counts. The cheapest overview |
| `search_logs` | Records filtered by `text` (match_all) and/or `where`, with optional `fields` |
| `run_sql` | Any single SELECT/WITH (aggregations, `histogram(...)`, GROUP BY) |
| `search_traces` | One line per trace: duration, spans, errors, services, trace_id |
| `get_trace` | Span tree with durations and offsets, exceptions with key frames; N+1 runs collapsed |
| `query_metrics` | PromQL range or instant query summarized per series |

Every tool is annotated `readOnlyHint`. Errors come back as MCP tool errors with a hint for what to do next. An
unexpected exception, which is a bug, is also returned as a tool error, and its backtrace is logged to the server's
stderr.

Layout:
- `lib/observability_mcp/tools/*`: one `MCP::Tool` per tool.
- `lib/observability_mcp/schemas/*`: tool input schemas, written with [Schematist](https://github.com/crmne/schematist).
- `search_query.rb`: builds the `_search` request.
- `time_range.rb`: parses time windows.
- `formatter.rb`, `trace_tree.rb`, `metrics_summary.rb`: render the compact output.
- `client.rb`: the HTTP client.

Input schemas use Schematist, not dry-schema, because the SDK already validates arguments against the JSON Schema with
`json_schemer`. What was missing was a readable way to write those schemas with descriptions, enums and defaults.
