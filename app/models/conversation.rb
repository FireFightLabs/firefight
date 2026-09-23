# A person talking to the agent. An investigation is the job it starts when a question needs real
# work, and the two share the loop, the tools and the saved chat.
class Conversation < ApplicationRecord
  KIND_CHANNEL = "channel"
  KIND_PERSONAL = "personal"
  # Another agent asking over MCP, one chat per principal, as that principal.
  KIND_MCP = "mcp"
  KINDS = [ KIND_CHANNEL, KIND_PERSONAL, KIND_MCP ].freeze

  TITLE_LIMIT = 80
  PREVIEW_LIMIT = 90
  # How long an owed answer counts as still coming. Shared with the reply job's lock, so the two give up together.
  REPLY_CEILING = 30.minutes
  SEARCH_LIMIT = 20
  UNTITLED = "New chat".freeze

  # The title is the person's own words, so it is encrypted like the messages.
  encrypts :title

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  # A person, a service key or an agent, whoever the way in resolved to.
  belongs_to :started_by, polymorphic: true, optional: true
  has_one :chat, as: :owner, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :personal, -> { where(kind: KIND_PERSONAL) }
  scope :personal_for, ->(member) { personal.where(started_by: member) }
  scope :archived, -> { where.not(archived_at: nil) }
  # Archived last, so a list that loads page by page reaches them at the end.
  scope :in_reading_order, -> { order(Arel.sql("archived_at IS NOT NULL, pinned_at DESC NULLS LAST, updated_at DESC")) }

  # The chat an outside agent has with Halon, one per principal and per incident it asks about, so
  # questions carry on and a question about one incident never lands in another's chat.
  def self.for_mcp!(workspace:, principal:, incident: nil)
    scope = workspace.conversations.where(kind: KIND_MCP, started_by: principal, subject: incident)
    scope.first || begin
      limits = workspace.conversation_limits
      workspace.conversations.create!(
        kind: KIND_MCP, started_by: principal, subject: incident,
        max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
      )
    end
  end

  def self.start_personal!(workspace:, member:)
    limits = workspace.conversation_limits
    workspace.conversations.create!(
      kind: KIND_PERSONAL, started_by: member,
      max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
    )
  end

  # The nav and the socket ask this, so neither offers what the gateway would refuse.
  def self.readable_by?(member)
    return false unless member

    member.may?(Ability::Action::RESOURCE_CHATS, Ability::Action::ACTION_READ, member.workspace)
  end

  # Titles and messages are encrypted, so matching happens in Ruby, not SQL.
  def self.search_for(member, text, limit: SEARCH_LIMIT)
    wanted = text.to_s.strip.downcase
    return [] if wanted.empty?

    personal_for(member).includes(chat: :last_readable_message).in_reading_order.to_a
      .select { |conversation| "#{conversation.display_title} #{conversation.preview}".downcase.include?(wanted) }
      .first(limit)
  end

  def personal? = kind == KIND_PERSONAL

  def mcp? = kind == KIND_MCP

  # What the person and the agent said to each other is the conversation, so it is never put away.
  # The work in between is, meaning the tool calls, their results and the agent's nudges to itself.
  def keeps_in_memory?(message)
    Chat::Message::READABLE_ROLES.include?(message.role) && !message.nudge && message.ruby_llm_tool_calls.empty?
  end

  # A conversation holds no records of its own beyond the chat, so there is nothing to add.
  def memory_brief = nil

  # Saved before the job runs, so the person sees it at once and a retried job asks only once. From here an answer is owed.
  def ask!(question)
    chat_record.add_message(role: Chat::Message::ROLE_USER, content: question)
    update!(title: question.truncate(TITLE_LIMIT)) if title.blank?
    expect_reply!
  end

  # The page shows the agent working from this, never from the shape of the last message, which the empty reply
  # RubyLLM saves before the model answers changes within milliseconds of the question.
  def expect_reply! = update_in_place!(answer_owed_since: Time.current)

  def reply_delivered! = update_in_place!(answer_owed_since: nil)

  # A turn owed this long belongs to a dead worker, and neither the page nor the queue waits on it.
  def answer_owed? = answer_owed_since.present? && answer_owed_since > REPLY_CEILING.ago

  # Saved, so the notice is still there on the next visit.
  def note!(text)
    chat_record.add_message(role: Chat::Message::ROLE_ASSISTANT, content: text)
  end

  def display_title = title.presence || UNTITLED

  def pinned? = pinned_at.present?

  def archived? = archived_at.present?

  def pin!(pinned) = update_in_place!(pinned_at: pinned ? Time.current : nil)

  def archive!(archived) = update_in_place!(archived_at: archived ? Time.current : nil)

  def rename!(new_title) = update_in_place!(title: new_title.to_s.strip.truncate(TITLE_LIMIT))

  def preview
    chat&.last_readable_message&.content.to_s.truncate(PREVIEW_LIMIT)
  end

  def watchable_by?(user)
    personal? && started_by.is_a?(WorkspaceMembership) && started_by.user_id == user&.id && self.class.readable_by?(started_by)
  end

  # Two questions asked at once share the chat that won the insert.
  def chat_record
    chat || Chat.open!(owner: self, workspace: workspace, model_choice: ai_model).tap { |opened| self.chat = opened }
  rescue ActiveRecord::RecordNotUnique
    reload_chat
  end

  def ai_model = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace)

  # The ledger and the prompt want an incident. A conversation about nothing has none.
  def incident
    subject if subject_type == Incident.name
  end

  def incident_id
    subject_id if subject_type == Incident.name
  end

  # Added in SQL, so a caller holding a stale copy cannot write an old total back.
  def add_turn!(turns:, spent_micros:)
    self.class.where(id: id).update_all([
      "turns_used = turns_used + ?, spent_micros = spent_micros + ?, updated_at = ?",
      turns, spent_micros, Time.current
    ])
  end

  private

  # Tidying a chat is not talking in it, so it keeps its place in the list.
  def update_in_place!(attributes)
    self.record_timestamps = false
    update!(attributes)
  ensure
    self.record_timestamps = true
  end
end
