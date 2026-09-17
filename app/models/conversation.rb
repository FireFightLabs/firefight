# A person talking to the agent. An investigation is the job it starts when a question needs real
# work, and the two share the loop, the tools and the saved chat.
class Conversation < ApplicationRecord
  KIND_CHANNEL = "channel"
  KIND_PERSONAL = "personal"
  KINDS = [ KIND_CHANNEL, KIND_PERSONAL ].freeze

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :started_by, class_name: "WorkspaceMembership", optional: true
  has_one :chat, as: :owner, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :personal, -> { where(kind: KIND_PERSONAL) }

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

  # The first thing the person asked, which is what a list of chats should say.
  def opening_line
    chat&.messages&.detect { |message| message.role == "user" }&.content.to_s.truncate(80)
  end

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

  # Two mentions in one thread can answer at once, so the higher count wins rather than the later write.
  # The agent holds its own grants, but an answer read by one person must not reach past what that
  # person could have read themselves.
  def refuse_for_asker!(action_key)
    raise AbilityGateway::Denied.new(action_key) unless started_by

    AbilityGateway.authorize!(
      principal: started_by, action_key: action_key, workspace: workspace, context: ledger_context
    )
  end

  def record_turn!(turns_used:, spent_cents:)
    self.class.where(id: id).update_all([
      "turns_used = GREATEST(turns_used, ?), spent_cents = GREATEST(spent_cents, ?), updated_at = ?",
      turns_used, spent_cents, Time.current
    ])
  end

  def over_budget? = spent_cents >= max_spend_cents
end
