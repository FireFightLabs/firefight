class AgentChatsController < InertiaController
  CHATS_PER_PAGE = 50
  CHAT_PAGE_PARAM = "page"

  # Shared with the page through lib/typescript_constants.rb, since partial visits ask for props by name.
  PROP_CONVERSATIONS = "conversations"
  PROP_ARCHIVED_COUNT = "archivedCount"
  PROP_CONVERSATION = "conversation"
  PROP_MESSAGES = "messages"
  PROP_INCIDENTS = "incidents"
  PROP_CONFIRMATIONS = "confirmations"
  PROP_INTEGRATION_CARDS = "integrationCards"
  PROP_ENVIRONMENTS = "environments"
  # The runs the open chat started, which its cards draw, and the one the address asks to open over the chat.
  PROP_INVESTIGATIONS = "investigations"
  PROP_OPEN_INVESTIGATION = "openInvestigation"
  PROP_CHARTS = "charts"
  # What the person sent while the agent worked, which joins the answer at its next step.
  PROP_WAITING_MESSAGES = "waitingMessages"
  PROPS = {
    "CONVERSATIONS" => PROP_CONVERSATIONS, "ARCHIVED_COUNT" => PROP_ARCHIVED_COUNT,
    "CONVERSATION" => PROP_CONVERSATION, "MESSAGES" => PROP_MESSAGES, "INCIDENTS" => PROP_INCIDENTS,
    "CONFIRMATIONS" => PROP_CONFIRMATIONS, "INTEGRATION_CARDS" => PROP_INTEGRATION_CARDS,
    "ENVIRONMENTS" => PROP_ENVIRONMENTS, "INVESTIGATIONS" => PROP_INVESTIGATIONS,
    "OPEN_INVESTIGATION" => PROP_OPEN_INVESTIGATION, "CHARTS" => PROP_CHARTS, "WAITING_MESSAGES" => PROP_WAITING_MESSAGES
  }.freeze
  # The newest active incidents, the ones people ask about.
  MENTIONABLE = 20
  NOTHING_ASKED = "Say something first."
  CHAT_DELETED = "Chat deleted."

  # Asking spends money, so it needs the same permission as starting an investigation.
  authorizes Ability::Action::RESOURCE_CHATS, read: %i[index show search], update: %i[update], delete: %i[destroy]
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[create ask confirm]
  authorizes Ability::Action::RESOURCE_INCIDENTS, read: %i[incidents]

  before_action :require_agent!

  # Sent empty so a partial visit here clears the open chat instead of keeping the last one.
  def index
    render inertia: "agent/index", props: base_props.merge(
      PROP_CONVERSATION => nil, PROP_MESSAGES => [], PROP_CONFIRMATIONS => [], PROP_INVESTIGATIONS => [], PROP_OPEN_INVESTIGATION => nil,
      PROP_CHARTS => [], PROP_WAITING_MESSAGES => []
    )
  end

  def show
    render inertia: "agent/index", props: base_props.merge(
      PROP_CONVERSATION => AgentChatSerializer.one(conversation),
      PROP_MESSAGES => AgentChatMessageSerializer.many(conversation.chat&.readable_messages&.includes(ruby_llm_tool_calls: :result) || []),
      PROP_CONFIRMATIONS => AgentChatConfirmationSerializer.many(conversation.chat&.awaiting_decision || []),
      PROP_INVESTIGATIONS => InvestigationCardSerializer.many(started_investigations),
      PROP_OPEN_INVESTIGATION => open_investigation,
      PROP_CHARTS => ChatChartSerializer.many(conversation.chat&.charts || []),
      PROP_WAITING_MESSAGES => AgentChatWaitingMessageSerializer.many(conversation.chat&.queued_messages&.waiting || [])
    )
  end

  def search
    render json: AgentChatSerializer.many(Conversation.search_for(current_membership, params[:q]))
  end

  def incidents
    render json: AgentChatIncidentSerializer.many(mentionable_incidents.search(params[:q].to_s.strip))
  end

  def create
    return redirect_to(agent_chats_path, alert: NOTHING_ASKED) if question.blank?

    chat = Conversation::Asking.start_personal(workspace: current_workspace, member: current_membership, question: question)
    redirect_to agent_chat_path(chat)
  end

  def ask
    return redirect_to(agent_chat_path(conversation), alert: NOTHING_ASKED) if question.blank?

    Conversation::Asking.ask(conversation, question, asker: current_membership)
    redirect_to agent_chat_path(conversation)
  end

  # The turn carries on as whoever answered, not whoever asked.
  def confirm
    decisions = Array(params[:decisions]).map do |decision|
      { tool_call_id: decision[:tool_call_id].to_s, approved: ActiveModel::Type::Boolean.new.cast(decision[:approved]) }
    end
    Conversation::Confirming.decide(conversation, decisions, by: current_membership)
    redirect_to agent_chat_path(conversation)
  end

  def update
    return rename if params.key?(:title)
    return pin if params.key?(:pinned)
    return archive if params.key?(:archived)

    redirect_to agent_chat_path(conversation)
  end

  # Deleting the open chat goes to an empty one, deleting any other keeps the person where they were.
  def destroy
    conversation.destroy!

    return redirect_to(agent_chats_path, notice: CHAT_DELETED) if came_from?(agent_chat_path(conversation))

    redirect_back_or_to agent_chats_path, notice: CHAT_DELETED
  end

  private

  def started_investigations
    conversation.investigations.seen.includes(:subject, :finding).order(:created_at)
  end

  # Only a run this chat started opens over it. Any other opens nothing.
  def open_investigation
    id = params[Investigation::QUERY_PARAM]
    investigation = id.presence && conversation.investigations.seen.find_by(id: id)
    investigation && InvestigationDetailSerializer.one(investigation)
  end

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
    @conversation ||= own_chats.find(params[:id])
  end

  def base_props
    {
      PROP_CONVERSATIONS => InertiaRails.scroll(chat_page_metadata) { AgentChatSerializer.many(chat_page) },
      PROP_ARCHIVED_COUNT => own_chats.archived.count,
      PROP_INCIDENTS => AgentChatIncidentSerializer.many(mentionable_incidents),
      # What an integrations card draws, read fresh on every visit, so returning from connecting shows it connected.
      PROP_INTEGRATION_CARDS => reads_integrations? ? IntegrationCardSerializer.many(IntegrationProvider.cards_for(current_workspace)) : [],
      PROP_ENVIRONMENTS => reads_integrations? ? EnvironmentOptionSerializer.many(current_workspace.environment_entries) : []
    }
  end

  def reads_integrations?
    current_membership.may?(Ability::Action::RESOURCE_INTEGRATIONS, Ability::Action::ACTION_READ, current_workspace)
  end

  def chat_page_number = [ params[CHAT_PAGE_PARAM].to_i, 1 ].max

  # One row over a page says whether there is another, without a count.
  def chat_page_rows
    @chat_page_rows ||= own_chats.includes(chat: :last_readable_message).in_reading_order
      .offset((chat_page_number - 1) * chats_per_page).limit(chats_per_page + 1).to_a
  end

  def chats_per_page = CHATS_PER_PAGE

  def chat_page = chat_page_rows.first(chats_per_page)

  def chat_page_metadata
    {
      page_name: CHAT_PAGE_PARAM,
      current_page: chat_page_number,
      previous_page: chat_page_number > 1 ? chat_page_number - 1 : nil,
      next_page: chat_page_rows.size > chats_per_page ? chat_page_number + 1 : nil
    }
  end

  def mentionable_incidents
    current_workspace.incidents.active.order(created_at: :desc).limit(MENTIONABLE)
  end

  def own_chats = current_workspace.conversations.personal_for(current_membership)

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end
end
