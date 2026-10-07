module Ability
  # A scope maps dimension to allowed catalog-entry ids. A missing dimension
  # means unrestricted, an empty array is invalid and never means all.
  module Scope
    DIMENSION_ENVIRONMENT = "environment"
    DIMENSION_SERVICE = "service"
    DIMENSIONS = [ DIMENSION_ENVIRONMENT, DIMENSION_SERVICE ].freeze
    # Reaches nothing anywhere. Only a member's default (WorkspaceMembership.default_target?) is held this way, so an
    # admin can take it away at once. It is its own key rather than an empty dimension, which a form could read as all.
    NO_ACCESS_KEY = "no_access"
    NO_ACCESS = { NO_ACCESS_KEY => true }.freeze

    # Unrestricted is spelled as the dimension being absent. Ids outside the
    # workspace's own environments are dropped.
    def self.for_environments(workspace, environment_ids)
      ids = workspace.environment_entries.where(id: Array(environment_ids).map(&:to_s).reject(&:blank?)).pluck(:id)
      ids.any? ? { DIMENSION_ENVIRONMENT => ids } : {}
    end

    def self.no_access?(scope) = scope.is_a?(Hash) && (scope[NO_ACCESS_KEY] || scope[NO_ACCESS_KEY.to_sym]) == true

    def self.covers?(grant_scope, requested)
      grant_scope.all? do |dimension, allowed|
        value = requested[dimension] || requested[dimension.to_sym]
        value.present? && allowed.include?(value)
      end
    end

    def self.validate(scope, errors, attribute: :scope)
      return errors.add(attribute, "must be a hash") unless scope.is_a?(Hash)
      return if scope.stringify_keys == NO_ACCESS

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
