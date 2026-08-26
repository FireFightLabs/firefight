# Thanking someone for their work on an incident. The record and the channel
# message are one operation, which is why this is not left in the handler that
# happens to open the modal.
class ShoutoutService
  def initialize(workspace)
    @workspace = workspace
  end

  def give(incident:, from:, to:, message:)
    blocked_reason = incident.shoutout_blocked_reason
    raise Incident::NotActive, blocked_reason if blocked_reason

    shoutout = Shoutout.create!(incident: incident, from_member: from, to_member: to, message: message)

    result = @workspace.adapter.post_shoutout_message(
      channel_id: incident.channel_id, incident: incident, from: from, to: to, message: message
    )
    shoutout.update_column(:message_ts, result[:message_id])

    shoutout
  end
end
