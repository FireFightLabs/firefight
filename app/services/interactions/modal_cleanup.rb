module Interactions
  # Shared cleanup helpers for modal-submit handlers.
  #
  # Modals that take more than a moment to fill in (incident update, close,
  # escalate, ...) are paired with a temporary "writing..." message posted to
  # the incident channel before the modal opens. On submit, the temp message
  # needs to be deleted. The coordinates ride in `private_metadata`.
  module ModalCleanup
    # Deletes the temp message identified by `metadata.channel_id` and
    # `metadata.temp_message_ts`. No-op when either coordinate is absent.
    # Swallows `AdapterError` — failure to delete is not user-visible and
    # should not surface as a submission error.
    def self.delete_temp_message(workspace, metadata)
      return if metadata.temp_message_ts.blank? || metadata.channel_id.blank?

      workspace.adapter.delete_message(channel_id: metadata.channel_id, ts: metadata.temp_message_ts)
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.modal_cleanup.delete_temp_failed", error: e.message })
    end
  end
end
