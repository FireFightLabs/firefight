# A Firefight token a tool minted goes to the person the call ran as and never to a model. In Halon's chat it waits on a
# card that mints it again when they open it (Chat::SecretEntry::KIND_TOKEN). For an outside agent it is shown to its
# person in the platform, in a message only they see. Either way the answer a model reads carries a placeholder, and
# Firefight keeps only the token's digest.
class TokenHandoff
  class Undelivered < StandardError; end

  UNREACHABLE = "Firefight shows a new token only to the person it is for, never to an agent, and has no direct message to " \
                "show it to you in. Create it in Firefight instead, from Gateway then Agents, or Developer then API keys. " \
                "It is shown to you once there.".freeze

  # Whether a token minted now for an outside agent's call can reach the person behind it.
  def self.reachable?(principal, workspace)
    principal.is_a?(WorkspaceMembership) && principal.platform_user_id.present? && workspace.chat_connected?
  end

  # Shows the token to the person in the platform and answers what the agent reads in its place. A token that could not
  # be shown is switched off at once, so no token nobody saw stays live.
  def self.to_person!(token, principal:, workspace:)
    key = key_of(token)
    WorkspaceAdapter.for(workspace).post_token_once(user_id: principal.platform_user_id, title: key.name, token: token)
    "Shown once to #{principal.display_name} in a direct message only they see. Firefight keeps no copy."
  rescue AdapterError => error
    key&.update!(active: false)
    Rails.logger.warn({ event: "token_handoff.undelivered", api_key_id: key&.id, error: error.class.name }.to_json)
    raise Undelivered, "The direct message with the token could not reach #{principal.display_name}, so the token was revoked. " \
                       "Issue a new one in Firefight."
  end

  # Leaves a card in the chat for its person and answers what Halon reads in its place.
  def self.to_card!(token, chat:, tool_call_id:, requester:)
    entry = Chat::SecretEntry.record_token!(chat: chat, tool_call_id: tool_call_id, api_key: key_of(token), requester: requester)
    SecretEntryJob.perform_later(entry.id)
    entry.withheld_words
  end

  # A token minted where nobody can be shown it is switched off at once.
  def self.discard!(token)
    key_of(token).update!(active: false)
    "A new token can be shown only to the person it is for, and nobody here can see it, so it was switched off. Issue one in Firefight."
  end

  def self.key_of(token) = ApiKey.find_by!(token_digest: ApiKey.digest_token(token.to_s))
  private_class_method :key_of
end
