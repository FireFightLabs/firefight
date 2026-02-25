class SummaryModalOpener
  def self.open(workspace:, incident:, trigger_id:, user_id:)
    adapter = WorkspaceAdapter.for(workspace)

    result = adapter.post_message(
      channel_id: incident.channel_id,
      text: ":writing_hand: <@#{user_id}> is updating the incident summary...",
      blocks: nil
    )

    metadata = {
      incident_id: incident.id,
      temp_message_ts: result[:message_ts],
      channel_id: incident.channel_id
    }.to_json

    adapter.open_summary_modal(trigger_id: trigger_id, incident: incident, private_metadata: metadata)
  rescue AdapterError::TriggerExpired
    cleanup_temp_message(adapter, incident.channel_id, result&.dig(:message_ts))
    raise
  end

  def self.cleanup_temp_message(adapter, channel_id, ts)
    return unless ts

    adapter.delete_message(channel_id: channel_id, ts: ts)
  rescue AdapterError => e
    Rails.logger.warn({ event: "summary_modal_opener.cleanup_temp_failed", error: e.message })
  end
  private_class_method :cleanup_temp_message
end
