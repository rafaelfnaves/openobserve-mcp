# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class ListStreams < Schematist::Schema
      extend Common

      target_params
      string :type, required: false, enum: Common::STREAM_TYPES, description: 'Only streams of this type. Default: all.'
      string :filter, required: false, description: 'Case-insensitive substring the stream name must contain.'
    end
  end
end
