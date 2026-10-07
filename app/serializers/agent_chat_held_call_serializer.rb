# A call the agent made in this chat that an approval rule held, from waiting for an approver to how it ended. What the
# viewer may do is shipped as blocked reasons, so the card never decides from a status which buttons work.
class AgentChatHeldCallSerializer < BaseSerializer
  object_as :held_call

  type :string
  def id
    held_call.id
  end

  type Chat::HeldCall::STATUSES.map(&:inspect).join(" | ")
  def status
    shown.status
  end

  # Such as "Ana approved: Api request on Faylee (Northflank), project faylee. Run it now?"
  type :string
  def headline
    shown.headline
  end

  type :string
  def call_name
    shown.call
  end

  type :string, optional: true
  def target
    shown.target
  end

  type "string[][]"
  def asked
    shown.asked
  end

  # How things stand now, in Halon's words, and what kind of change it found, said plainly above them.
  type :string, optional: true
  def state
    shown.state
  end

  type Chat::CurrentState::CHANGES.map(&:inspect).join(" | "), optional: true
  def change
    held_call.state_change
  end

  type :string, optional: true
  def warning
    shown.warning
  end

  type :string, optional: true
  def checked_at
    shown.checked_at&.iso8601
  end

  type :string, optional: true
  def expires_at
    shown.expires_at&.iso8601
  end

  # When the card last had news, which is where it sits among the chat's messages.
  type :string
  def at
    (held_call.approval.resolved_at || held_call.created_at).utc.iso8601(3)
  end

  type :string, optional: true
  def decided_by
    shown.decided_by
  end

  type :string, optional: true
  def result
    shown.result
  end

  type :string, optional: true
  def run_blocked_reason
    held_call.run_blocked_reason(options[:member]) if offered?(Chat::CurrentState::ACTION_RUN)
  end

  type :string, optional: true
  def dismiss_blocked_reason
    held_call.dismiss_blocked_reason(options[:member]) if offered?(Chat::CurrentState::ACTION_DISMISS)
  end

  type :string, optional: true
  def ask_again_blocked_reason
    held_call.ask_again_blocked_reason(options[:member]) if offered?(Chat::CurrentState::ACTION_ASK_AGAIN)
  end

  # What the card offers at all in this state. A button offered but blocked stays visible, with why.
  type "string[]"
  def offers
    shown.offers
  end

  private

  def offered?(action) = shown.offers.include?(action)

  def shown = memo.fetch(:shown) { Conversation::HeldCalls.shown(held_call) }
end
