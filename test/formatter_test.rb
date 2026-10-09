# frozen_string_literal: true

require 'test_helper'

class FormatterTest < Minitest::Test
  Formatter = ObservabilityMcp::Formatter
  TS = 1_790_856_000_000_000

  def test_uniform_narrow_rows_render_as_a_table
    output = Formatter.rows([{ 'service' => 'a', 'n' => 3 }, { 'service' => 'b', 'n' => 1 }])

    assert_equal "service | n\na | 3\nb | 1", output
  end

  def test_records_factor_out_common_fields_and_drop_noise_and_empty_values
    hits = [
      { '_timestamp' => TS, 'service_name' => 'api', 'body' => 'boom', 'telemetry_sdk_name' => 'otel', 'x' => '' },
      { '_timestamp' => TS + 1_000, 'service_name' => 'api', 'body' => 'ok', 'status' => 500, 'events' => '[]' }
    ]

    assert_equal <<~TEXT.chomp, Formatter.rows(hits)
      common: service_name=api
      2026-10-01T12:00:00.000Z | body=boom
      2026-10-01T12:00:00.001Z | body=ok | status=500
    TEXT
  end

  def test_requested_fields_are_kept_even_when_noisy
    output = Formatter.rows([{ 'telemetry_sdk_name' => 'otel', 'body' => 'x' }], fields: %w[telemetry_sdk_name])

    assert_equal "telemetry_sdk_name\notel", output
  end

  def test_truncates_long_values_and_escapes_newlines
    output = Formatter.rows([{ 'a' => 1, 'b' => 2, 'c' => 3, 'd' => 4, 'e' => 5, 'f' => 6, 'g' => 7, 'h' => 8, 'msg' => "line1\nline2#{'x' * 50}" }], max_chars: 20)

    assert_includes output, 'msg=line1\nline2xxxxxxxx…(+42 chars)'
  end

  def test_records_tolerate_non_integer_timestamps_and_empty_rows
    output = Formatter.rows([{ '_timestamp' => '2026-10-01T11:00:00', 'status' => 500 }, { 'x' => nil }, { 'n' => 1, 'm' => 2 }])

    assert_equal "2026-10-01T11:00:00 | status=500\n(all fields empty)\nn=1 | m=2", output
    assert_equal '(2 rows, all fields empty)', Formatter.rows([{ 'a' => '' }, {}])
  end

  def test_hides_filebeat_bookkeeping
    row = { 'agent_id' => 'a', 'agent_ephemeral_id' => 'b', 'log_file_inode' => 1, 'log_offset' => 2, '_version' => '1',
            'host_name' => 'ip-10', 'message' => 'boom', 'level' => 'error' }

    assert_equal "host_name | message | level\nip-10 | boom | error", Formatter.rows([row])
  end

  def test_helpers
    assert_equal 'doc count unavailable', Formatter.doc_count(-3_163_677)
    assert_equal '1,500 docs', Formatter.doc_count(1_500)
    assert_equal '1,234,567', Formatter.number(1_234_567)
    assert_equal '-1,234.5', Formatter.number(-1_234.5)
    assert_equal '0', Formatter.number(nil)
    assert_equal '78.7ms', Formatter.duration_ms(78_713)
    assert_equal '1.78s', Formatter.duration_ms(1_777_179)
  end

  def test_redacts_credential_like_keys_nested_json_and_auth_headers
    row = { 'password' => 'hunter2', 'accessToken' => 'abc', 'X-Api-Key' => 'k', 'gen_ai_usage_total_tokens' => 42,
            'params' => { 'user' => 'ana', 'client_secret' => 's3', 'items' => [{ 'session_id' => 'x' }] },
            'message' => 'GET /cars Authorization: Bearer eyJhbGciOi.payload.sig-_ done' }

    output = Formatter.rows([row], max_chars: 500)

    assert_equal <<~TEXT.chomp, output
      password | accessToken | X-Api-Key | gen_ai_usage_total_tokens | params | message
      [REDACTED] | [REDACTED] | [REDACTED] | 42 | {"user":"ana","client_secret":"[REDACTED]","items":[{"session_id":"[REDACTED]"}]} | GET /cars Authorization: Bearer [REDACTED] done
    TEXT
    refute_match(/hunter2|abc|s3|eyJ/, output)
  end
end
