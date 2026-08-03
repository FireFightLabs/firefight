module Mcp
  # Conditions match on ids, but an agent knows slugs. Accept either, and
  # refuse anything that resolves to neither: a stored value matching no record
  # produces a condition that saves cleanly and then never fires.
  module ConditionValues
    def self.resolve(workspace, condition)
      values = Array(condition[:values]).map(&:to_s)
      scope = scope_for(workspace, condition[:condition_field])
      return values unless scope

      by_slug = scope.pluck(:slug, :id).to_h
      known_ids = by_slug.values.to_set

      values.map do |value|
        next value if known_ids.include?(value)
        next by_slug[value] if by_slug.key?(value)

        raise ArgumentError,
          "unknown #{condition[:condition_field]} #{value.inspect}. Valid: #{by_slug.keys.sort.join(', ')}"
      end
    end

    # Custom field conditions carry option ids, which have no slug to resolve
    # against, so they pass through untouched.
    def self.scope_for(workspace, condition_field)
      case condition_field
      when IncidentCondition::FIELD_SEVERITY      then workspace.incident_severities.active
      when IncidentCondition::FIELD_INCIDENT_TYPE then workspace.incident_types.active
      end
    end
  end
end
