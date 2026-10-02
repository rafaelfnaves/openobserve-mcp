# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class RunSql < Schematist::Schema
      extend Common

      target_params
      string :sql, description: 'A single SELECT/WITH statement (PostgreSQL-like dialect). Stream names are quoted ' \
                                'automatically; a LIMIT is added when missing. Do not filter _timestamp here — use ' \
                                'since/from/to.'
      stream_type_param
      time_window_params(default: '1h')
      limit_param(default: 50, maximum: 500)
      max_chars_param
    end
  end
end
