# The agent's saved chat with the model. A restarted or resumed job continues from it.
class Chat < ApplicationRecord
  acts_as_chat messages: :messages, message_class: "Chat::Message"

  belongs_to :workspace
  belongs_to :owner, polymorphic: true
  has_many :saved_results, -> { in_order }, class_name: "Chat::SavedResult", dependent: :destroy, inverse_of: :chat

  # A tool result up to this share of the running model's window is handed over whole. A larger
  # one is saved and previewed, so a model with more room is given more without anything being retuned.
  RESULT_SHARE = 0.10
  CHARACTERS_PER_TOKEN = 4
  # For a model the registry knows nothing about.
  ASSUMED_WINDOW = 128_000

  # DISTINCT ON keeps one row per chat, so previews for a whole list load in one query.
  has_one :last_readable_message,
    -> {
      where(role: Chat::Message::READABLE_ROLES)
        .select("DISTINCT ON (chat_messages.chat_id) chat_messages.*")
        .order("chat_messages.chat_id, chat_messages.created_at DESC")
    },
    class_name: "Chat::Message", inverse_of: false

  validate :owner_in_same_workspace

  # Only the two sides of the conversation, not the system prompt or tool results.
  def readable_messages
    messages.where(role: Chat::Message::READABLE_ROLES).order(:created_at)
  end

  # Requested is ours, RubyLLM reads anything but approved or denied as undecided.
  APPROVAL_REQUESTED = "requested"
  APPROVAL_APPROVED = "approved"
  APPROVAL_DENIED = "denied"

  def tool_calls
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: messages.select(:id))
  end

  def awaiting_decision = tool_calls.where(approval: APPROVAL_REQUESTED).order(:created_at)

  def request_decisions!(tool_call_ids)
    tool_calls.where(tool_call_id: tool_call_ids, approval: nil).update_all(approval: APPROVAL_REQUESTED)
  end

  # One guarded update, so a second click on the same question loses rather than deciding it twice.
  def decide!(tool_call_id, approved:)
    decision = approved ? APPROVAL_APPROVED : APPROVAL_DENIED
    tool_calls.where(tool_call_id: tool_call_id, approval: APPROVAL_REQUESTED).update_all(approval: decision, updated_at: Time.current) > 0
  end

  # The calls put to the person in the same pause as this one.
  def asked_with(tool_call_id)
    message_id = tool_calls.where(tool_call_id: tool_call_id).pick(:message_id)
    tool_calls.where(message_id: message_id).where.not(approval: nil).order(:created_at)
  end

  def unfinished_tool_names = tool_calls.where(result_id: nil).distinct.pluck(:name)

  # In characters, since that is what a tool hands back. Tokens are only estimated from them.
  def result_limit
    window = model&.context_window.to_i
    window = ASSUMED_WINDOW unless window.positive?
    (window * RESULT_SHARE * CHARACTERS_PER_TOKEN).to_i
  end

  # Records which model will run, without opening a connection to the provider.
  def self.open!(owner:, workspace:, model_choice:)
    chat = new(owner: owner, workspace: workspace)
    chat.provider = model_choice.provider if model_choice.provider.present?
    chat.assume_model_exists = model_choice.provider.present? && !FirefightAi.registered?(model_choice.model)
    chat.model = model_choice.model
    chat.save!
    chat
  end

  # A killed worker leaves an empty reply that RubyLLM reads as the final answer. Only the job holding the run may call this.
  def discard_interrupted_reply!
    last_message = messages.reload.last
    return unless last_message&.interrupted_reply?

    last_message.destroy!
    messages.reset
  end

  private

  def owner_in_same_workspace
    return if owner.nil? || owner.workspace_id == workspace_id

    errors.add(:owner, "must belong to the same workspace")
  end
end
