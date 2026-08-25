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
    errors.concat(approver_errors(requirement["approvers"], workspace))
    errors
  end

  def self.approver_errors(approvers, workspace)
    return [] if approvers.nil?
    return [ "approvers must be a list of members" ] unless approvers.is_a?(Array)
    return [] if approvers.empty? || workspace.nil?

    known = workspace.workspace_memberships.where(id: approvers).count
    known == approvers.uniq.size ? [] : [ "approvers must all be members of this workspace" ]
  end
  private_class_method :approver_errors
end
