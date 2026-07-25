# Outcome vocabulary + write-time validation for the approvals domain: which
# role must approve, and how many approvers (v1 supports exactly one).
module PolicyRule::ApprovalOutcome
  REQUIRE_KEY = "require"
  SUPPORTED_COUNT = 1

  def self.errors_for(outcome)
    return [ "outcome must be an object" ] unless outcome.is_a?(Hash)

    requirement = outcome.with_indifferent_access[REQUIRE_KEY]
    return [ "outcome must contain a '#{REQUIRE_KEY}' object" ] unless requirement.is_a?(Hash)

    errors = []
    role = requirement["role"]
    errors << "unknown role #{role.inspect}" unless WorkspaceMembership.roles.key?(role.to_s)
    errors << "count must be #{SUPPORTED_COUNT} (multi-approver comes later)" unless requirement["count"].to_i == SUPPORTED_COUNT
    unless requirement["self_approval"].nil? || [ true, false ].include?(requirement["self_approval"])
      errors << "self_approval must be true or false"
    end
    errors
  end
end
