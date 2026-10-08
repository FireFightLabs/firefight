# A secret a tool call in a chat handed to a person (Chat::SecretEntry), from the card appearing to the value being set
# or the credential revealed. The card is drawn in the chat, and a chat in a Slack thread gets a message pointing to it,
# since a value is never typed into Slack. Every value passes straight from the request to the provider, through the
# gateway as the person the call ran as, and is never kept, logged or handed to Halon.
class SecretEntryService
  Result = Data.define(:ok, :words)
  Revealed = Data.define(:value, :words)

  def self.recorded!(entry)
    Conversation::LiveDelivery.secret_entry_moved(entry.conversation)
    conversation = entry.conversation
    return if conversation.thread_id.blank?

    posted = WorkspaceAdapter.for(entry.workspace).post_secret_entry(channel_id: conversation.channel_id, thread_id: conversation.thread_id, entry: entry)
    entry.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id])
  rescue AdapterError => error
    Rails.logger.warn({ event: "secret_entry.unposted", secret_entry_id: entry.id, error: error.class.name }.to_json)
  end

  # Sends the value the person typed, once. A failure opens the field again and says why.
  def self.fill!(entry, value:, by:)
    blocked = entry.fill_blocked_reason(by)
    return Result.new(ok: false, words: blocked) if blocked
    return Result.new(ok: false, words: "Type the value first.") if value.to_s.empty?
    return Result.new(ok: false, words: entry.reload.fill_blocked_reason(by) || "This field is closed.") unless entry.claim!

    begin
      said = Integration::SecretHandoff.fill!(tool: entry.tool, catalog_entry_id: entry.catalog_entry_id, target: entry.target, value: value,
                                              principal: by, source: AbilityGateway::SOURCE_WEB)
    rescue AbilityGateway::Denied
      entry.released!
      return Result.new(ok: false, words: "You can no longer use #{entry.tool.integration.display_name}'s #{entry.tool.name}, so nothing was set.")
    rescue Integrations::Error => error
      entry.released!
      return Result.new(ok: false, words: Integrations::Sentence.all("Nothing was set.", error))
    end

    entry.filled!(by)
    moved!(entry)
    Result.new(ok: true, words: said)
  end

  # The credential the card names, read from the provider now, for its person only.
  def self.reveal(entry, by:)
    blocked = entry.reveal_blocked_reason(by)
    return Revealed.new(value: nil, words: blocked) if blocked

    Revealed.new(value: Integration::SecretHandoff.resolve(entry.reference, workspace: entry.workspace, principal: by, source: AbilityGateway::SOURCE_WEB),
                 words: nil)
  rescue AbilityGateway::Denied
    Revealed.new(value: nil, words: "You can no longer use #{entry.tool.integration.display_name}'s #{entry.tool.name}, so it cannot be shown.")
  rescue Integrations::Error => error
    Revealed.new(value: nil, words: Integrations::Sentence.all("It could not be read.", error))
  end

  # The card and its Slack message say how it stands now.
  def self.moved!(entry)
    Conversation::LiveDelivery.secret_entry_moved(entry.conversation)
    return if entry.message_id.blank?

    WorkspaceAdapter.for(entry.workspace).update_secret_entry(channel_id: entry.message_channel_id, message_id: entry.message_id, entry: entry)
  rescue AdapterError => error
    Rails.logger.warn({ event: "secret_entry.redraw_failed", secret_entry_id: entry.id, error: error.class.name }.to_json)
  end
  private_class_method :moved!
end
