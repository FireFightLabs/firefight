module Interactions
  # Slow modals are paired with a temporary "writing..." message in the channel,
  # its coordinates ride in private_metadata.
  module ModalCleanup
    # Failure to delete is not user-visible, so AdapterError never becomes a submission error.
    def self.delete_temp_message(workspace, metadata)
      return if metadata.temp_message_ts.blank? || metadata.channel_id.blank?

      workspace.adapter.delete_message(channel_id: metadata.channel_id, message_id: metadata.temp_message_ts)
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.modal_cleanup.delete_temp_failed", error: e.message })
    end

    # The item already exists, a prompt that lingers is not worth failing the submission over.
    def self.dismiss_prompt(workspace, metadata)
      return if metadata.prompt_handle.blank?

      workspace.adapter.dismiss_prompt(prompt_handle: metadata.prompt_handle)
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.modal_cleanup.dismiss_prompt_failed", error: e.message })
    end
  end
end
