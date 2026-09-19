# Tool calls act as the person who asked, so a chat reaches exactly what they can in the dashboard.
class Conversation::Turn
  attr_reader :conversation, :asker

  delegate :workspace, :incident, to: :conversation

  def initialize(conversation, asker:)
    @conversation = conversation
    @asker = asker
  end

  def acting_principal = asker

  # A turn nobody can be credited with does nothing.
  def tool_call(action_key:, params: {}, &block)
    raise AbilityGateway::Denied.new(action_key) unless asker

    Chat::ToolCall.run!(
      workspace: workspace, principal: asker, action_key: action_key, params: params,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.incident_id }, &block
    )
  end

  def refusal(action_key)
    "Not allowed: #{asker_name} cannot use #{action_key} in this workspace. Tell them, and that a workspace admin can grant it."
  end

  # Starting a run spends money and posts in the channel, so it goes through the full gateway, approval rules included.
  def start_investigation(&)
    action_key = Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
    raise AbilityGateway::Denied.new(action_key) unless asker

    AbilityGateway.authorize!(
      principal: asker, action_key: action_key, workspace: workspace,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.incident_id }, &
    )
  end

  def asker_name = asker.try(:display_name) || "The person asking"
end
