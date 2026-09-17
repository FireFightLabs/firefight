# A person talking to the agent. An investigation is the job it starts when a question needs real
# work, and the two share the loop, the tools and the saved chat.
class Conversation < ApplicationRecord
  KIND_CHANNEL = "channel"
  KIND_PERSONAL = "personal"
  KINDS = [ KIND_CHANNEL, KIND_PERSONAL ].freeze

  TITLE_LIMIT = 80
  PREVIEW_LIMIT = 90
  UNTITLED = "New chat".freeze

  # The title is the person's own words, the same customer data as the messages it was taken from.
  encrypts :title

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :started_by, class_name: "WorkspaceMembership", optional: true
  has_one :chat, as: :owner, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :personal, -> { where(kind: KIND_PERSONAL) }
  scope :pinned, -> { where.not(pinned_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :unarchived, -> { where(archived_at: nil) }
  # Pinned chats sit at the top of the list, the rest by when they were last spoken to.
  scope :in_reading_order, -> { order(Arel.sql("pinned_at DESC NULLS LAST, updated_at DESC")) }

  # A chat in the dashboard belongs to one person. Nobody else sees it, and the agent reads only
  # what that person could read.
  def self.start_personal!(workspace:, member:)
    limits = workspace.conversation_limits
    workspace.conversations.create!(
      kind: KIND_PERSONAL, started_by: member,
      max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
    )
  end

  def personal? = kind == KIND_PERSONAL

  # The question is written down before the job runs, so the person sees their own words straight
  # away and a retried job asks the model the same thing once.
  def ask!(question)
    chat_record.add_message(role: Chat::Message::ROLE_USER, content: question)
    update!(title: question.truncate(TITLE_LIMIT)) if title.blank?
  end

  # What the agent says when it stops without answering. Saved, so it is still there on the next
  # visit rather than only in whatever was on screen at the time.
  def note!(text)
    chat_record.add_message(role: Chat::Message::ROLE_ASSISTANT, content: text)
  end

  def display_title = title.presence || UNTITLED

  def pinned? = pinned_at.present?

  def archived? = archived_at.present?

  def pin!(pinned) = update!(pinned_at: pinned ? Time.current : nil)

  def archive!(archived) = update!(archived_at: archived ? Time.current : nil)

  def rename!(new_title) = update!(title: new_title.to_s.strip.truncate(TITLE_LIMIT))

  # The last thing said, which is what a list of chats shows under each title.
  def preview
    chat&.readable_messages&.last&.content.to_s.truncate(PREVIEW_LIMIT)
  end

  # A personal chat is read by one person in the dashboard, and by nobody else.
  def watchable_by?(user)
    personal? && started_by.present? && started_by.user_id == user&.id
  end

  # One chat per conversation, so two questions asked at once share the one that won.
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

  # Answers in a channel are read by everyone there, so the agent's own account decides what it reads.
  def agent_principal = SystemAgent.investigator

  def tool_call(action_key:, params: {}, &block)
    refuse_for_asker!(action_key) if personal?

    Chat::ToolCall.run!(
      workspace: workspace, principal: agent_principal, action_key: action_key,
      params: params, context: ledger_context, &block
    )
  end

  def ledger_context
    {
      source: AbilityGateway::SOURCE_CONVERSATION,
      incident_id: incident_id,
      triggered_by_label: started_by.try(:principal_label)
    }
  end

  # The agent holds its own grants, but an answer read by one person must not reach past what that
  # person could have read themselves. This asks the gateway rather than running the call as them,
  # so the ledger keeps one row for the call the agent actually makes.
  def refuse_for_asker!(action_key)
    raise AskerDenied.new(action_key) unless asker_may?(action_key)
  end

  # Whether the person being answered could have done this themselves.
  def asker_may?(action_key)
    return false unless started_by

    action = Ability::Action.lookup(action_key, workspace)
    action.present? &&
      AbilityGateway.permitted?(started_by, action, action_key, workspace, {}) && action.configured_for?({})
  end

  # Starting a run spends money and posts in the channel, so the person asking needs the same
  # permission they would need to type the command.
  def asker_may_start_investigation?
    asker_may?(
      Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
    )
  end

  # Two mentions in one thread can answer at once, so the higher count wins rather than the later write.
  def record_turn!(turns_used:, spent_cents:)
    self.class.where(id: id).update_all([
      "turns_used = GREATEST(turns_used, ?), spent_cents = GREATEST(spent_cents, ?), updated_at = ?",
      turns_used, spent_cents, Time.current
    ])
  end

  def over_budget? = spent_cents >= max_spend_cents

  # The person asking is the one without the grant, not the agent, and the agent is told so it can
  # say the right thing.
  class AskerDenied < AbilityGateway::Denied; end
end
