# One conversation per thread, so a second mention joins the one already there.
class Conversation::Opener
  def self.call(workspace:, incident:, channel_id:, thread_id:, platform_user_id:)
    existing = workspace.conversations.find_by(channel_id: channel_id, thread_id: thread_id)
    return existing if existing

    limits = workspace.conversation_limits
    workspace.conversations.create!(
      subject: incident, kind: Conversation::KIND_CHANNEL, channel_id: channel_id, thread_id: thread_id,
      started_by: member(workspace, platform_user_id),
      max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
    )
  rescue ActiveRecord::RecordNotUnique
    workspace.conversations.find_by!(channel_id: channel_id, thread_id: thread_id)
  end

  def self.member(workspace, platform_user_id)
    WorkspaceMemberProvisioner.find_or_provision!(
      workspace: workspace, platform_user_id: platform_user_id, adapter: workspace.adapter
    )
  end
  private_class_method :member
end
