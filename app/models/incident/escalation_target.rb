# Who an escalation is aimed at. Usually a member, but the platform may know
# someone this workspace has no membership row for, and escalating to a person
# is not what makes them a billable member. It answers the same questions any
# actor does, so a message names it without asking which kind it is.
class Incident::EscalationTarget
  attr_reader :member, :platform_user_id, :actor_display_name, :avatar_url

  def initialize(member: nil, platform_user_id: nil, name: nil, avatar_url: nil)
    @member = member
    @platform_user_id = platform_user_id
    @actor_display_name = name
    @avatar_url = avatar_url
  end

  def self.for_member(member)
    new(
      member: member,
      platform_user_id: member.platform_user_id,
      name: member.actor_display_name,
      avatar_url: member.user.avatar_url
    )
  end

  # Rebuilt from what a workflow or a job carried, which is the metadata the
  # escalation event already stores.
  def self.from_metadata(workspace, metadata)
    metadata = metadata.to_h.with_indifferent_access
    member = workspace.workspace_memberships.find_by(id: metadata[:escalated_to_member_id])
    return for_member(member) if member

    new(
      platform_user_id: metadata[:escalated_to_platform_user_id],
      name: metadata[:escalated_to_name],
      avatar_url: metadata[:escalated_to_avatar_url]
    )
  end

  def to_metadata
    {
      escalated_to_platform_user_id: platform_user_id,
      escalated_to_member_id: member&.id,
      escalated_to_name: actor_display_name,
      escalated_to_avatar_url: avatar_url
    }.compact
  end
end
