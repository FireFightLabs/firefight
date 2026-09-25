# The agent's saved chat with the model. A restarted or resumed job continues from it.
class Chat < ApplicationRecord
  # The library sends the model whatever this association holds, so it is the messages still in
  # play. messages is everything ever said, which is what a person reads and a replay needs.
  acts_as_chat messages: :sent_messages, message_class: "Chat::Message"
  has_many :sent_messages, -> { where(archived_at: nil).order(:created_at, :id) },
           class_name: "Chat::Message", dependent: :destroy, inverse_of: :chat
  has_many :messages, -> { order(:created_at, :id) }, class_name: "Chat::Message", dependent: :destroy, inverse_of: :chat

  include Chat::Compacting

  belongs_to :workspace
  belongs_to :owner, polymorphic: true
  has_many :saved_results, -> { in_order }, class_name: "Chat::SavedResult", dependent: :destroy, inverse_of: :chat
  has_many :charts, -> { in_order }, class_name: "Chat::Chart", dependent: :delete_all, inverse_of: :chat
  has_many :queued_messages, class_name: "Chat::QueuedMessage", dependent: :delete_all, inverse_of: :chat

  # The registry holds no context window for the model this chat runs on. Nothing is assumed in
  # its place, so an operator adds the model to the registry with its window.
  class UnknownWindow < StandardError; end

  # A tool result up to this share of the running model's window is handed over whole. A larger
  # one is saved and previewed, so a model with more room is given more without anything being retuned.
  RESULT_SHARE = 0.10
  CHARACTERS_PER_TOKEN = 4

  # DISTINCT ON keeps one row per chat, so previews for a whole list load in one query.
  has_one :last_readable_message,
    -> {
      where(role: Chat::Message::READABLE_ROLES, nudge: false)
        .select("DISTINCT ON (chat_messages.chat_id) chat_messages.*")
        .order("chat_messages.chat_id, chat_messages.created_at DESC")
    },
    class_name: "Chat::Message", inverse_of: false

  validate :owner_in_same_workspace

  # Only the two sides of the conversation, not the system prompt, tool results or the agent's nudges to itself.
  def readable_messages
    messages.where(role: Chat::Message::READABLE_ROLES, nudge: false).order(:created_at)
  end

  def queue_message!(content, sender:)
    queued_messages.create!(content: content, sender: sender)
  end

  # Adds what was sent while the agent worked, in the order it was sent, and returns what it added. from limits it to one
  # person's messages, since a chat turn acts with the permissions of whoever asked it. The block words each message.
  def take_queued!(from: nil)
    waiting = queued_messages.waiting
    waiting = waiting.where(sender: from) if from
    waiting.to_a.select(&:take!).each do |queued|
      add_message(role: Chat::Message::ROLE_USER, content: block_given? ? yield(queued) : queued.content)
    end
  end

  # RubyLLM saves a stop on the chat's row and checks it while a model call runs, so a stop pressed in the web process
  # reaches the worker. Read from the row, since this record may be one the worker loaded before the stop.
  def stop_requested? = self.class.where(id: id).pick(:cancelled) == true

  def clear_stop! = update_column(:cancelled, false)

  # A stop can land after the model asked for tools and before they ran. Each such call is answered, since a provider
  # refuses a chat with a call and no result.
  def answer_unanswered_calls!(text)
    last = sent_messages.reload.where(role: Chat::Message::ROLE_ASSISTANT).last
    return unless last

    last.ruby_llm_tool_calls.where(result_id: nil).find_each do |call|
      add_message(role: Chat::Message::ROLE_TOOL, content: text, tool_call_id: call.tool_call_id)
    end
  end

  # The loop keeps the agent moving by speaking as the user, which is how a model reads it.
  # Marked, because the content is encrypted and nothing else could tell it from the person's words.
  def nudge!(text)
    add_message(role: Chat::Message::ROLE_USER, content: text).tap { |message| message.update!(nudge: true) }
  end

  # An answer held back for a check is the agent's own too, so it is marked like a nudge and never read to a person.
  def hold_last_reply!
    messages.where(role: Chat::Message::ROLE_ASSISTANT).reorder(created_at: :desc, id: :desc).first&.update!(nudge: true)
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

  # A refusal or an error is still a result the model reads, so the row alone cannot say it failed.
  def mark_failed!(tool_call_id)
    tool_calls.where(tool_call_id: tool_call_id).update_all(failed: true, updated_at: Time.current)
  end

  def failed_tool_call_ids = tool_calls.where(failed: true).order(:created_at).pluck(:tool_call_id)

  # In characters, since that is what a tool hands back. Tokens are only estimated from them.
  def result_limit = (context_window! * RESULT_SHARE * CHARACTERS_PER_TOKEN).to_i

  def context_window!
    window = model&.context_window.to_i
    raise UnknownWindow, "No context window is known for #{model_id}. Add it to the model registry." unless window.positive?

    window
  end

  # Appended, never reordered. The tool list sits at the front of every request, so the same
  # order every turn is what lets a provider reuse what it has already read.
  def remember_found_tools!(names)
    added = names.map(&:to_s) - found_tool_names
    update!(found_tool_names: found_tool_names + added) if added.any?
  end

  # A call left unfinished before tools were remembered still needs its tool.
  def known_tool_names = found_tool_names | unfinished_tool_names

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
    last_message = sent_messages.reload.last
    return unless last_message&.interrupted_reply?

    last_message.destroy!
    sent_messages.reset
    messages.reset
  end

  private

  def owner_in_same_workspace
    return if owner.nil? || owner.workspace_id == workspace_id

    errors.add(:owner, "must belong to the same workspace")
  end
end
