module Ability
  # Grant scope semantics, pinned by the gateway design. A scope is a hash
  # of dimension => allowed catalog-entry ids. A missing dimension means
  # unrestricted. An empty array is invalid (never a way to say "all").
  # A request matches when its value for every scoped dimension is in the
  # grant's list.
  module Scope
    DIMENSION_ENVIRONMENT = "environment"
    DIMENSION_SERVICE = "service"
    DIMENSIONS = [ DIMENSION_ENVIRONMENT, DIMENSION_SERVICE ].freeze

    # An empty environment list means unrestricted, which is spelled as the
    # dimension being absent. Ids that are not the workspace's own
    # environments are dropped rather than trusted.
    def self.for_environments(workspace, environment_ids)
      ids = workspace.environment_entries.where(id: Array(environment_ids).map(&:to_s).reject(&:blank?)).pluck(:id)
      ids.any? ? { DIMENSION_ENVIRONMENT => ids } : {}
    end

    def self.covers?(grant_scope, requested)
      grant_scope.all? do |dimension, allowed|
        value = requested[dimension] || requested[dimension.to_sym]
        value.present? && allowed.include?(value)
      end
    end

    def self.validate(scope, errors, attribute: :scope)
      return errors.add(attribute, "must be a hash") unless scope.is_a?(Hash)

      scope.each do |dimension, values|
        unless DIMENSIONS.include?(dimension.to_s)
          return errors.add(attribute, "unknown dimension '#{dimension}'")
        end
        unless values.is_a?(Array) && values.any? && values.all? { |v| v.is_a?(String) }
          errors.add(attribute, "'#{dimension}' must be a non-empty array of ids; omit the key for unrestricted")
        end
      end
    end
  end
end
