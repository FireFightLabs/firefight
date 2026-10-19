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

  # Such as "Halon wants to: pause dev-web" while it waits, then "Done: pause dev-web" once it ran.
  type :string
  def headline
    shown.headline
  end

  # The one line under it, such as "Waiting for a workspace admin to approve it." or why it failed.
  type :string
  def line
    shown.line
  end

  # A code change's parts while it runs and after, each with how it stands. Empty for any other call.
  STAGE_TYPE = "{ key: string; title: string; status: #{Chat::CodeFixProgress::STAGES.map(&:inspect).join(" | ")}; detail: string | null; link: string | null }[]".freeze
  type STAGE_TYPE
  def stages
    shown.progress&.stages&.map { |stage| stage.to_h.transform_keys(&:to_s) } || []
  end

  # The page a finished change made, such as its pull request. Absent when it made none.
  type :string, optional: true
  def link
    shown.link
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

  # What a counted database write touches, each a label and what it says, as the asker's card would have shown it.
  type "string[][]"
  def rows
    shown.rows
  end

  # The warning the asker's card would have carried when text from outside Firefight was read before the call.
  type :string, optional: true
  def caution
    shown.caution
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
