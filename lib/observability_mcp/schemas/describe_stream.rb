# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class DescribeStream < Schematist::Schema
      extend Common

      target_params
      stream_param
      stream_type_param
    end
  end
end
