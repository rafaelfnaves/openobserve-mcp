# observability-mcp

Read-only Ruby MCP server (stdio) for OpenObserve. Ruby 4.0.6 via mise.

## Commands
- `bundle exec rake test` - minitest + webmock suite; HTTP is always stubbed
- `bundle-audit check --update` - dependency CVE audit
- Tool tests go through JSON-RPC with `call_tool` (test/test_helper.rb), so input schemas are validated too
- Ruby 4: `benchmark` is no longer a default gem; time things with `Process.clock_gettime(Process::CLOCK_MONOTONIC)`

## Security invariants (keep when adding tools/output)
- Every request goes through `Client#build_uri`, which rejects `.`/`..`/empty org and stream names
- Every value shown to the model goes through `Formatter.redact` (credential-like keys and Bearer/Basic tokens)
- `SearchQuery.normalize` is for usability, not security: OpenObserve's `_search` endpoint is what keeps queries read-only
- Record contents are untrusted (prompt injection); `Server::INSTRUCTIONS` says so and must keep saying it

## Workflow
- Conventional commits (`feat:`, `fix:`, `chore:`)
- The `openobserve` MCP server running in a Claude session doesn't reload code; reconnect with `/mcp` after changes
