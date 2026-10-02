# frozen_string_literal: true

module ObservabilityMcp
  module Schemas
    class ListEnvironments < Schematist::Schema
      boolean :check_orgs, required: false, default: true,
                           description: 'Call each environment to list its organizations (also verifies credentials).'
    end
  end
end
