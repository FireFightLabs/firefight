# A person talking to the agent. An investigation is the job it starts when a question needs real
# work, and the two share the loop, the tools and the saved chat.
class Conversation < ApplicationRecord
  KIND_CHANNEL = "channel"
  KIND_PERSONAL = "personal"
  KINDS = [ KIND_CHANNEL, KIND_PERSONAL ].freeze

  TITLE_LIMIT = 80
  PREVIEW_LIMIT = 90
  SEARCH_LIMIT = 20
  UNTITLED = "New chat".freeze

  # The title is the person's own words, so it is encrypted like the messages.
  encrypts :title

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :started_by, class_name: "WorkspaceMembership", optional: true
  has_one :chat, as: :owner, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :personal, -> { where(kind: KIND_PERSONAL) }
  scope :personal_for, ->(member) { personal.where(started_by: member) }
  scope :archived, -> { where.not(archived_at: nil) }
  # Archived last, so a list that loads page by page reaches them at the end.
  scope :in_reading_order, -> { order(Arel.sql("archived_at IS NOT NULL, pinned_at DESC NULLS LAST, updated_at DESC")) }

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

    key = Ability::Action.system_key(Ability::Action::RESOURCE_CHATS, Ability::Action::ACTION_READ)
    member.permitted_to?(Ability::Action.lookup(key, member.workspace), member.workspace)
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

  # Saved before the job runs, so the person sees it at once and a retried job asks only once.
  def ask!(question)
    chat_record.add_message(role: Chat::Message::ROLE_USER, content: question)
    update!(title: question.truncate(TITLE_LIMIT)) if title.blank?
  end

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
    personal? && started_by.present? && started_by.user_id == user&.id && self.class.readable_by?(started_by)
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
