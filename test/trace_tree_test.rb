# frozen_string_literal: true

require 'test_helper'

class TraceTreeTest < Minitest::Test
  START = 1_790_856_000_000_000_000 # ns

  def span(id, parent, operation, offset_ms:, duration_ms:, service: 'api', **attributes)
    start = START + (offset_ms * 1_000_000)
    {
      'trace_id' => 'abc123', 'span_id' => id, 'reference_parent_span_id' => parent, 'service_name' => service,
      'operation_name' => operation, 'start_time' => start, 'end_time' => start + (duration_ms * 1_000_000),
      'duration' => duration_ms * 1_000, 'span_status' => 'UNSET'
    }.merge(attributes.transform_keys(&:to_s))
  end

  def exception_event(message)
    {
      'name' => 'exception', 'exception.type' => 'ValueError', 'exception.message' => message,
      'exception.stacktrace' => "Traceback (most recent call last):\n  File \"/app/main.py\", line 7, in handler\n    run()\n" \
                                "  File \"/app/db.py\", line 3, in run\n    raise ValueError('bad')\nValueError: bad"
    }
  end

  def test_renders_nested_spans_with_errors_and_collapsed_repetitions
    events = JSON.generate([exception_event('bad'), exception_event('bad')])
    spans = [
      span('r', '', 'GET /cars', offset_ms: 0, duration_ms: 120, http_status_code: '500'),
      *(1..4).map { span("q#{it}", 'r', 'SELECT cars', offset_ms: it, duration_ms: 2, db_system: 'postgresql') },
      span('w', 'r', 'enqueue', offset_ms: 10, duration_ms: 30, service: 'worker', span_status: 'ERROR',
                                status_message: 'ValueError: bad', events: events)
    ]

    assert_equal <<~TEXT.chomp, ObservabilityMcp::TraceTree.new(spans).render
      trace abc123 · 6 spans · 1 errors · 120.0ms · started 2026-10-01T12:00:00.000Z · services: api (5), worker (1)
      └─ [api] GET /cars 120.0ms @+0.0ms {http_status_code=500}
         ├─ ×4 SELECT cars total=8.0ms max=2.0ms @+1.0ms (repeated siblings collapsed)
         └─ ✗ [worker] enqueue 30.0ms @+10.0ms
              exception ValueError: bad
                File "/app/main.py", line 7, in handler → run()
                File "/app/db.py", line 3, in run → raise ValueError('bad')
    TEXT
  end

  def test_spans_with_missing_parents_become_roots
    spans = [span('a', 'gone', 'orphan', offset_ms: 5, duration_ms: 1), span('b', nil, 'root', offset_ms: 0, duration_ms: 9)]
    lines = ObservabilityMcp::TraceTree.new(spans).render.lines.map(&:chomp)

    assert_match(/\A⚠ partial trace: 1 spans point to parents that are not in this stream/, lines[1])
    assert_equal ['├─ [api] root 9.0ms @+0.0ms', '└─ [api] orphan 1.0ms @+5.0ms'], lines.drop(2)
  end

  def test_never_collapses_a_group_hiding_an_error_below_it
    spans = [
      span('r', nil, 'run', offset_ms: 0, duration_ms: 50),
      *(1..4).map { span("j#{it}", 'r', 'job', offset_ms: it, duration_ms: 5) },
      span('db', 'j3', 'query', offset_ms: 3, duration_ms: 1, span_status: 'ERROR', status_message: 'deadlock')
    ]
    output = ObservabilityMcp::TraceTree.new(spans).render

    refute_includes output, 'collapsed'
    assert_includes output, '✗ query 1.0ms @+3.0ms'
    assert_includes output, 'status: deadlock'
  end

  def test_spans_in_parent_cycles_are_still_rendered
    spans = [span('r', nil, 'root', offset_ms: 0, duration_ms: 9), span('a', 'b', 'a-op', offset_ms: 1, duration_ms: 1),
             span('b', 'a', 'b-op', offset_ms: 2, duration_ms: 1), span('s', 's', 'self', offset_ms: 3, duration_ms: 1)]
    output = ObservabilityMcp::TraceTree.new(spans).render

    %w[root a-op b-op self].each { assert_includes output, it }
    assert_equal 5, output.lines.size
  end

  def test_deep_chains_render_without_recursion_and_stop_indenting
    spans = (0...5_000).map { span("s#{it}", it.zero? ? nil : "s#{it - 1}", "op#{it}", offset_ms: it, duration_ms: 1) }
    lines = ObservabilityMcp::TraceTree.new(spans).render.lines

    assert_equal ObservabilityMcp::TraceTree::MAX_DEPTH + 2, lines.size
    assert_match(/… 4960 deeper spans not shown \(max depth 40\)/, lines.last)
  end

  def test_tolerates_missing_or_string_fields
    spans = [span('a', nil, 'root', offset_ms: 0, duration_ms: 1).merge('duration' => '1500', 'start_time' => nil),
             *(1..4).map { span("c#{it}", 'a', 'child', offset_ms: it, duration_ms: 1).merge('duration' => '1000') }]

    assert_includes ObservabilityMcp::TraceTree.new(spans).render, '×4 child total=4.0ms'
  end

  def test_redacts_sensitive_attributes_and_tokens_in_error_messages
    spans = [span('r', '', 'GET /cars', offset_ms: 0, duration_ms: 5, span_status: 'ERROR',
                                       http_request_header_authorization: 'Basic dXNlcjpwYXNz',
                                       status_message: 'upstream rejected Bearer abc.def')]

    output = ObservabilityMcp::TraceTree.new(spans, show_attributes: true).render

    assert_includes output, 'http_request_header_authorization=[REDACTED]'
    assert_includes output, 'status: upstream rejected Bearer [REDACTED]'
    refute_match(/dXNlcjpwYXNz|abc\.def/, output)
  end
end
