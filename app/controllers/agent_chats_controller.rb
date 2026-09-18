# The dashboard side of talking to the agent. A chat here is personal, so only the person who
# started it sees it, and the agent reads only what that person could read.
class AgentChatsController < InertiaController
  RECENT = 50
  # What @ offers in the composer. The live ones are the ones anybody asks about.
  MENTIONABLE = 20

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS,
    read: %i[index show],
    create: %i[create ask],
    update: %i[update],
    delete: %i[destroy]

  before_action :require_agent!

  def index
    render inertia: "agent/index", props: base_props
  end

  def show
    render inertia: "agent/index", props: base_props.merge(
      conversation: AgentChatSerializer.one(conversation),
      messages: AgentChatMessageSerializer.many(conversation.chat&.readable_messages || [])
    )
  end

  def create
    chat = Conversation.start_personal!(workspace: current_workspace, member: current_membership)

    redirect_to agent_chat_path(chat)
  end

  def ask
    question = params[:question].to_s.strip
    return redirect_to(agent_chat_path(conversation), alert: "Say something first.") if question.blank?

    conversation.ask!(question)
    ConversationReplyJob.perform_later(conversation.id)
    redirect_to agent_chat_path(conversation)
  end

  # Renaming, pinning and archiving are each one small change to the chat itself.
  def update
    return rename if params.key?(:title)
    return pin if params.key?(:pinned)
    return archive if params.key?(:archived)

    redirect_to agent_chat_path(conversation)
  end

  def destroy
    conversation.destroy!

    redirect_to agent_chats_path, notice: "Chat deleted."
  end

  private

  def rename
    title = params[:title].to_s.strip
    return redirect_back_or_to(agent_chat_path(conversation), alert: "A chat needs a name.") if title.blank?

    conversation.rename!(title)
    redirect_back_or_to agent_chat_path(conversation), notice: "Chat renamed."
  end

  def pin
    pinned = ActiveModel::Type::Boolean.new.cast(params[:pinned])
    conversation.pin!(pinned)

    redirect_back_or_to agent_chat_path(conversation), notice: pinned ? "Chat pinned." : "Chat unpinned."
  end

  def archive
    archived = ActiveModel::Type::Boolean.new.cast(params[:archived])
    conversation.archive!(archived)

    redirect_back_or_to agent_chat_path(conversation), notice: archived ? "Chat archived." : "Chat back in the list."
  end

  def conversation
    @conversation ||= current_workspace.conversations.personal
      .where(started_by: current_membership).find(params[:id])
  end

  def base_props
    {
      conversations: AgentChatSerializer.many(recent_conversations),
      incidents: AgentChatIncidentSerializer.many(mentionable_incidents)
    }
  end

  def mentionable_incidents
    current_workspace.incidents.active.order(created_at: :desc).limit(MENTIONABLE)
  end

  # Archived chats come too, since the page keeps them behind their own filter.
  def recent_conversations
    current_workspace.conversations.personal.where(started_by: current_membership)
      .in_reading_order.limit(RECENT)
  end

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end
end
