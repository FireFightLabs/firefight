# The dashboard side of talking to the agent. A chat here is personal, so only the person who
# started it sees it, and the agent reads only what that person could read.
class AgentChatsController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS,
    read: %i[index show],
    create: %i[create ask]

  before_action :require_agent!

  def index
    render inertia: "agent/index", props: base_props
  end

  def show
    render inertia: "agent/index", props: base_props.merge(
      conversation: AgentChatSerializer.one(conversation),
      messages: AgentChatMessageSerializer.many(conversation.chat&.messages&.reload || [])
    )
  end

  def create
    chat = Conversation.start_personal!(workspace: current_workspace, member: current_membership)

    redirect_to agent_chat_path(chat)
  end

  def ask
    question = params[:question].to_s.strip
    return redirect_to(agent_chat_path(conversation), alert: "Say something first.") if question.blank?

    ConversationReplyJob.perform_later(conversation.id, question)
    redirect_to agent_chat_path(conversation)
  end

  private

  def conversation
    @conversation ||= current_workspace.conversations.personal
      .where(started_by: current_membership).find(params[:id])
  end

  def base_props
    { conversations: AgentChatSerializer.many(recent_conversations) }
  end

  def recent_conversations
    current_workspace.conversations.personal.where(started_by: current_membership)
      .order(updated_at: :desc).limit(50).includes(chat: :messages)
  end

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end
end
