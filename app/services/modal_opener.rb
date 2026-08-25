# Opens one of the incident modals from a command or a button.
#
# A placeholder message goes into the channel first so the channel shows that
# something is happening while the responder is in the dialog, and its id rides
# in the modal's private metadata so the submission handler can delete it.
#
class ModalOpener
  MODALS = {
    cancel:   { emoji: ":wastebasket:",     doing: "canceling the incident",             modal: PlatformAdapter::Modal::INCIDENT_CANCEL },
    close:    { emoji: ":lock:",            doing: "closing the incident",               modal: PlatformAdapter::Modal::INCIDENT_CLOSE },
    escalate: { emoji: ":rotating_light:",  doing: "escalating the incident",            modal: PlatformAdapter::Modal::ESCALATE },
    reopen:   { emoji: ":rotating_light:",  doing: "reopening the incident",             modal: PlatformAdapter::Modal::REOPEN },
    summary:  { emoji: ":writing_hand:",    doing: "updating the incident summary",      modal: PlatformAdapter::Modal::SUMMARY },
    update:   { emoji: ":writing_hand:",    doing: "writing an internal status update",  modal: PlatformAdapter::Modal::INCIDENT_UPDATE }
  }.freeze

  def self.open(kind, workspace:, incident:, trigger_id:, user_id:)
    config = MODALS.fetch(kind)
    adapter = workspace.adapter

    result = adapter.post_message(
      channel_id: incident.channel_id,
      text: "#{config[:emoji]} <@#{user_id}> is #{config[:doing]}...",
      blocks: nil
    )

    metadata = ModalState.encode(
      incident_id: incident.id,
      temp_message_ts: result[:message_id],
      channel_id: incident.channel_id
    )

    view = adapter.build_modal(config[:modal], incident, metadata: metadata)
    adapter.open_modal(trigger_id: trigger_id, view: view)
  rescue AdapterError::TriggerExpired
    cleanup_temp_message(adapter, incident.channel_id, result&.dig(:message_id))
    raise
  end

  def self.cleanup_temp_message(adapter, channel_id, message_id)
    return unless message_id

    adapter.delete_message(channel_id: channel_id, message_id: message_id)
  rescue AdapterError => e
    Rails.logger.warn({ event: "modal_opener.cleanup_temp_failed", error: e.message })
  end
  private_class_method :cleanup_temp_message
end
