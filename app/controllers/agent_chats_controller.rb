# The dashboard side of talking to the agent. A chat here is personal, so only the person who
# started it sees it, and the agent reads only what that person could read.
class AgentChatsController < InertiaController
  RECENT = 50
  # What @ offers in the composer. The live ones are the ones anybody asks about.
  MENTIONABLE = 20
  NOTHING_ASKED = "Say something first."
  CHAT_DELETED = "Chat deleted."

  # A chat is the person's own to read and tidy. Asking the agent spends money, so it is the same
  # permission as starting an investigation.
  authorizes Ability::Action::RESOURCE_CHATS, read: %i[index show], update: %i[update], delete: %i[destroy]
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[create ask]

  before_action :require_agent!

  def index
    render inertia: "agent/index", props: base_props
  end

  def show
    render inertia: "agent/index", props: base_props.merge(
      conversation: AgentChatSerializer.one(conversation),
      messages: AgentChatMessageSerializer.many(conversation.chat&.readable_messages&.includes(:ruby_llm_tool_calls) || [])
    )
  end

  def create
    return redirect_to(agent_chats_path, alert: NOTHING_ASKED) if question.blank?

    chat = Conversation::Asking.start_personal(workspace: current_workspace, member: current_membership, question: question)
    redirect_to agent_chat_path(chat)
  end

  def ask
    return redirect_to(agent_chat_path(conversation), alert: NOTHING_ASKED) if question.blank?

    Conversation::Asking.ask(conversation, question)
    redirect_to agent_chat_path(conversation)
  end

  # Renaming, pinning and archiving are each one small change to the chat itself.
  def update
    return rename if params.key?(:title)
    return pin if params.key?(:pinned)
    return archive if params.key?(:archived)

    redirect_to agent_chat_path(conversation)
  end

  # Deleting the chat that is open leaves nothing to go back to. Deleting another from the list
  # keeps the person where they were.
  def destroy
    conversation.destroy!

    return redirect_to(agent_chats_path, notice: CHAT_DELETED) if came_from?(agent_chat_path(conversation))

    redirect_back_or_to agent_chats_path, notice: CHAT_DELETED
  end

  private

  def question = params[:question].to_s.strip

  def came_from?(path)
    URI.parse(request.referer.to_s).path == path
  rescue URI::InvalidURIError
    false
  end

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
      .includes(chat: :last_readable_message).in_reading_order.limit(RECENT)
  end

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end
end
