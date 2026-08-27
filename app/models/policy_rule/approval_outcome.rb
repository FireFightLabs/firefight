# Outcome vocabulary + write-time validation for the approvals domain. Which
# role or which named people must approve, where they are asked, and whether
# the requester may approve their own request. One approver decides (v1).
module PolicyRule::ApprovalOutcome
  REQUIRE_KEY = "require"
  SUPPORTED_COUNT = 1

  NOTIFY_CHANNEL = "channel"
  NOTIFY_DM = "dm"
  NOTIFY_BOTH = "both"
  NOTIFY_OPTIONS = [ NOTIFY_CHANNEL, NOTIFY_DM, NOTIFY_BOTH ].freeze

  def self.build(role:, self_approval: true, notify: nil, approvers: [], agents_may_approve: false)
    {
      REQUIRE_KEY => {
        "role" => role.to_s,
        "count" => SUPPORTED_COUNT,
        "self_approval" => ActiveModel::Type::Boolean.new.cast(self_approval),
        "notify" => notify.presence || NOTIFY_CHANNEL,
        "approvers" => Ability::Principal.references(approvers),
        "agents_may_approve" => ActiveModel::Type::Boolean.new.cast(agents_may_approve)
      }
    }
  end

  def self.requirement(outcome)
    outcome.with_indifferent_access[REQUIRE_KEY] || {}
  end

  def self.errors_for(outcome, workspace: nil)
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
    unless requirement["notify"].nil? || NOTIFY_OPTIONS.include?(requirement["notify"])
      errors << "notify must be one of #{NOTIFY_OPTIONS.join(', ')}"
    end
    unless requirement["agents_may_approve"].nil? || [ true, false ].include?(requirement["agents_may_approve"])
      errors << "agents_may_approve must be true or false"
    end
    errors.concat(approver_errors(requirement, workspace))
    errors
  end

  # Every named approver must be a principal of this workspace, and a
  # machine can only be named when the rule says agents may decide.
  def self.approver_errors(requirement, workspace)
    approvers = requirement["approvers"]
    return [] if approvers.nil?
    return [ "approvers must be a list of principals" ] unless approvers.is_a?(Array)
    return [] if approvers.empty? || workspace.nil?

    references = Ability::Principal.references(approvers)
    return [ "approvers must all be members, agents or service keys of this workspace" ] if references.any? { |ref| Ability::Principal.find_reference(workspace, ref).nil? }

    machines = references.reject { |ref| ref["kind"] == Ability::Principal::KIND_USER }
    return [] if machines.empty? || requirement["agents_may_approve"] == true

    [ "an agent or service key can only approve when agents_may_approve is on" ]
  end
  private_class_method :approver_errors
end
