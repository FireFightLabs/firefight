# Shows a secret a chat's tool call handed to a person where the chat lives, outside the turn that made it.
class SecretEntryJob < ApplicationJob
  queue_as :conversations

  def perform(secret_entry_id)
    entry = Chat::SecretEntry.find_by(id: secret_entry_id)
    SecretEntryService.recorded!(entry) if entry
  end
end
