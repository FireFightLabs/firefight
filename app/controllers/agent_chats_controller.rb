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
  # What the composer takes, and whether the open chat's model reads images.
  PROP_ATTACHMENT_RULES = "attachmentRules"
  # Each time the open chat made room in the model's window, placed among the steps by when it happened.
  PROP_COMPACTIONS = "compactions"
  # Calls an approval rule held in the open chat, from waiting for an approver to how they ended.
  PROP_HELD_CALLS = "heldCalls"
  # Changes Halon was refused in the open chat for want of a pack, each with Ask an admin.
  PROP_PACK_REFUSALS = "packRefusals"
  # Secrets a tool call in the open chat handed to the person who asked, to type or to reveal, never their values.
  PROP_SECRET_ENTRIES = "secretEntries"
  # What Halon watches for the open chat, going and ended, and every line the watches said, placed by when they said it.
  PROP_WATCHES = "watches"
  PROP_WATCH_UPDATES = "watchUpdates"
  # What Halon said about pull requests it opened from this chat that need attention, each with Fix it.
  PROP_PULL_REQUEST_NOTICES = "pullRequestNotices"
  # Memories something contradicted in this chat, each asking the person which is right.
  PROP_MEMORY_QUESTIONS = "memoryQuestions"
  # The checks Halon handed to helpers in this chat, each drawn under the step that started it with the steps it took.
  PROP_HELPERS = "helpers"
  # Setup's Meet Halon step, while an admin is on it: the question to start with, and whether Halon has answered.
  PROP_SETUP_GUIDE = "setupGuide"
  # The plans Halon keeps in the open chat, each a checklist that moves as it works.
  PROP_PLANS = "plans"
  # Statements Halon ran that changed rows, with their counts, check and the copy kept of the rows.
  PROP_DATA_REPAIRS = "dataRepairs"
  # Changes customers feel that Halon made, undone when their time is up unless someone keeps them.
  PROP_MITIGATIONS = "mitigations"
  # Owners asked before Halon stopped something they started.
  PROP_OWNER_ASKS = "ownerAsks"
  PROPS = {
    "CONVERSATIONS" => PROP_CONVERSATIONS, "ARCHIVED_COUNT" => PROP_ARCHIVED_COUNT,
    "CONVERSATION" => PROP_CONVERSATION, "MESSAGES" => PROP_MESSAGES, "INCIDENTS" => PROP_INCIDENTS,
    "CONFIRMATIONS" => PROP_CONFIRMATIONS, "INTEGRATION_CARDS" => PROP_INTEGRATION_CARDS,
    "ENVIRONMENTS" => PROP_ENVIRONMENTS, "INVESTIGATIONS" => PROP_INVESTIGATIONS,
    "OPEN_INVESTIGATION" => PROP_OPEN_INVESTIGATION, "CHARTS" => PROP_CHARTS, "WAITING_MESSAGES" => PROP_WAITING_MESSAGES,
    "ATTACHMENT_RULES" => PROP_ATTACHMENT_RULES, "COMPACTIONS" => PROP_COMPACTIONS, "HELD_CALLS" => PROP_HELD_CALLS,
    "PACK_REFUSALS" => PROP_PACK_REFUSALS, "SECRET_ENTRIES" => PROP_SECRET_ENTRIES, "SETUP_GUIDE" => PROP_SETUP_GUIDE, "WATCHES" => PROP_WATCHES, "WATCH_UPDATES" => PROP_WATCH_UPDATES,
    "PULL_REQUEST_NOTICES" => PROP_PULL_REQUEST_NOTICES, "MEMORY_QUESTIONS" => PROP_MEMORY_QUESTIONS, "PLANS" => PROP_PLANS,
    "DATA_REPAIRS" => PROP_DATA_REPAIRS, "MITIGATIONS" => PROP_MITIGATIONS, "OWNER_ASKS" => PROP_OWNER_ASKS, "HELPERS" => PROP_HELPERS
  }.freeze
  # The newest active incidents, the ones people ask about.
  MENTIONABLE = 20
  NOTHING_ASKED = "Say something first."
  SECRET_GONE = "That secret is no longer in this chat."
  CHAT_DELETED = "Chat deleted."

  include ServesChatAttachment

  # Asking spends money, so it needs the same permission as starting an investigation.
  authorizes Ability::Action::RESOURCE_CHATS, read: %i[index show search investigation_file data_repair_copy],
                                             update: %i[update ask_pack fill_secret reveal_secret], delete: %i[destroy]
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[create ask confirm stop run_held_call dismiss_held_call ask_held_call_again stop_watch fix_pull_request
                                                                schedule_plan cancel_plan retry_plan undo_plan keep_mitigation extend_mitigation
                                                                undo_mitigation]
  authorizes Ability::Action::RESOURCE_INCIDENTS, read: %i[incidents]

  include RequiresAgent
  before_action :require_agent!
  # Setup's Meet Halon step is a chat here.
  skip_before_action :continue_setup

  # Sent empty so a partial visit here clears the open chat instead of keeping the last one.
  def index
    render inertia: "agent/index", props: base_props.merge(
      PROP_CONVERSATION => nil, PROP_MESSAGES => [], PROP_CONFIRMATIONS => [], PROP_INVESTIGATIONS => [], PROP_OPEN_INVESTIGATION => nil,
      PROP_CHARTS => [], PROP_WAITING_MESSAGES => [], PROP_ATTACHMENT_RULES => attachment_rules(nil), PROP_COMPACTIONS => [],
      PROP_HELD_CALLS => [], PROP_PACK_REFUSALS => [], PROP_SECRET_ENTRIES => [], PROP_WATCHES => [], PROP_WATCH_UPDATES => [],
      PROP_PULL_REQUEST_NOTICES => [], PROP_MEMORY_QUESTIONS => [], PROP_PLANS => [], PROP_DATA_REPAIRS => [], PROP_MITIGATIONS => [],
      PROP_OWNER_ASKS => [], PROP_HELPERS => []
    )
  end

  def show
    render inertia: "agent/index", props: base_props.merge(
      PROP_CONVERSATION => AgentChatSerializer.one(conversation),
      PROP_MESSAGES => AgentChatMessageSerializer.many(conversation.chat&.readable_messages&.includes(:attached_files, ruby_llm_tool_calls: :result) || [],
                                                       member: current_membership),
      PROP_CONFIRMATIONS => AgentChatConfirmationSerializer.many(conversation.chat&.awaiting_decision || []),
      PROP_INVESTIGATIONS => InvestigationCardSerializer.many(started_investigations),
      PROP_OPEN_INVESTIGATION => open_investigation,
      PROP_CHARTS => ChatChartSerializer.many(conversation.chat&.charts || []),
      PROP_WAITING_MESSAGES => AgentChatWaitingMessageSerializer.many(conversation.chat&.queued_messages&.waiting&.includes(:attached_files) || []),
      PROP_ATTACHMENT_RULES => attachment_rules(conversation.chat),
      PROP_COMPACTIONS => ChatCompactionSerializer.many(conversation.chat&.compactions || []),
      PROP_HELD_CALLS => AgentChatHeldCallSerializer.many(held_calls_shown, member: current_membership),
      PROP_PACK_REFUSALS => AgentChatPackRefusalSerializer.many(pack_refusals_shown, member: current_membership),
      PROP_SECRET_ENTRIES => AgentChatSecretEntrySerializer.many(conversation.chat&.secret_entries&.includes(:requester, :done_by, tool: :integration) || [],
                                                                 member: current_membership),
      PROP_WATCHES => AgentChatWatchSerializer.many(watches_shown, member: current_membership),
      PROP_WATCH_UPDATES => AgentChatWatchUpdateSerializer.many(watch_updates_shown),
      PROP_PULL_REQUEST_NOTICES => AgentChatPullRequestNoticeSerializer.many(pull_request_notices_shown, member: current_membership),
      PROP_MEMORY_QUESTIONS => AgentChatMemoryQuestionSerializer.many(conversation.memory_posts.order(:created_at), member: current_membership),
      PROP_PLANS => AgentChatPlanSerializer.many(plans_shown, member: current_membership),
      PROP_DATA_REPAIRS => AgentChatDataRepairSerializer.many(conversation.chat&.data_repairs&.where(status: Chat::DataRepair::STATUS_RAN) || []),
      PROP_MITIGATIONS => AgentChatMitigationSerializer.many(conversation.chat&.mitigations&.shown || [], member: current_membership),
      PROP_OWNER_ASKS => AgentChatOwnerAskSerializer.many(conversation.chat&.owner_asks&.shown || []),
      PROP_HELPERS => AgentChatHelperSerializer.many(conversation.chat&.helpers&.includes(:workspace, :own_chat) || [])
    )
  end

  # A file that went with a note to a run this chat started, for whoever may read the chat and so the run.
  def investigation_file
    investigation = conversation.investigations.seen.find(params[:investigation_id])
    send_chat_attachment(investigation.note_file(params[:file_id]))
  end

  def search
    render json: AgentChatSerializer.many(Conversation.search_for(current_membership, params[:q]))
  end

  def incidents
    render json: AgentChatIncidentSerializer.many(mentionable_incidents.search(params[:q].to_s.strip))
  end

  def create
    files = files_sent
    return redirect_to(agent_chats_path, alert: NOTHING_ASKED) if question.blank? && files.empty?

    chat = Conversation::Asking.start_personal(workspace: current_workspace, member: current_membership, question: question, files: files)
    redirect_to agent_chat_path(chat)
  rescue Chat::Attachment::Refused => refused
    redirect_to agent_chats_path, alert: refused.message
  end

  def ask
    files = files_sent
    return redirect_to(agent_chat_path(conversation), alert: NOTHING_ASKED) if question.blank? && files.empty?

    Conversation::Asking.ask(conversation, question, asker: current_membership, files: files)
    redirect_to agent_chat_path(conversation)
  rescue Chat::Attachment::Refused => refused
    redirect_to agent_chat_path(conversation), alert: refused.message
  end

  # The page shows the answer ending with Stopped once the worker stops.
  def stop
    blocked = conversation.stop_blocked_reason
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

    conversation.request_stop!
    redirect_to agent_chat_path(conversation)
  end

  # The turn carries on as whoever answered, not whoever asked. expires is when a change customers feel is undone.
  def confirm
    decisions = Array(params[:decisions]).map do |decision|
      { tool_call_id: decision[:tool_call_id].to_s, approved: ActiveModel::Type::Boolean.new.cast(decision[:approved]),
        for_chat: ActiveModel::Type::Boolean.new.cast(decision[:for_chat]), expires: decision[:expires].presence&.to_s }
    end
    Conversation::Confirming.decide(conversation, decisions, by: current_membership)
    redirect_to agent_chat_path(conversation)
  end

  # Approval unlocked the call, and only this runs it, once, as whoever asked. Halon then says how it went.
  def run_held_call
    decide_held_call("Running it now.") { |held| Conversation::HeldCalls.run!(held, by: current_membership) }
  end

  def dismiss_held_call
    decide_held_call("Dismissed. It will not run.") { |held| Conversation::HeldCalls.dismiss!(held, by: current_membership) }
  end

  def ask_held_call_again
    decide_held_call("Asked for approval again.") { |held| Conversation::HeldCalls.ask_again!(held, by: current_membership) }
  end

  # Stops what Halon was watching for this chat. It says so where the watch reports.
  def stop_watch
    watch = conversation.chat&.watches&.find_by(id: params[:watch_id])
    return redirect_to(agent_chat_path(conversation), alert: "That watch is no longer in this chat.") unless watch

    blocked = Conversation::Watches.stop!(watch, by: current_membership)
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

    redirect_to agent_chat_path(conversation), notice: %(Stopped watching "#{watch.title}".)
  end

  # Schedule on a plan waiting for its time. It runs then, as whoever approved it, once a fresh reading says nothing moved.
  def schedule_plan
    decide_plan { |plan| [ Conversation::Plans.approve!(plan, by: current_membership), "Plan scheduled for #{plan.reload.run_at_words}." ] }
  end

  def cancel_plan
    decide_plan { |plan| [ Conversation::Plans.cancel!(plan, by: current_membership), "Plan cancelled. Nothing in it will run." ] }
  end

  # Retry on a plan that stopped. Halon reads how things stand and carries on from the step that failed, as whoever pressed it.
  def retry_plan
    decide_plan { |plan| [ Conversation::Plans.retry!(plan, by: current_membership), "Halon is trying the plan again." ] }
  end

  # Undo has Halon put back what the plan changed, from the undo each change was written with. Each change still asks.
  def undo_plan
    decide_plan { |plan| [ Conversation::Plans.undo!(plan, by: current_membership), "Halon is undoing the plan." ] }
  end

  def keep_mitigation
    decide_mitigation { |mitigation| [ Conversation::Mitigations.keep!(mitigation, by: current_membership), "#{mitigation.label} is kept." ] }
  end

  def extend_mitigation
    decide_mitigation do |mitigation|
      [ Conversation::Mitigations.extend!(mitigation, by: current_membership),
        "#{mitigation.label} has #{Chat::Mitigation.duration_words(Chat::Mitigation::EXTEND_BY.in_minutes.to_i)} more." ]
    end
  end

  def undo_mitigation
    decide_mitigation { |mitigation| [ Conversation::Mitigations.undo_now!(mitigation, by: current_membership), "Undoing #{mitigation.label}." ] }
  end

  # The rows a statement touched, as they were right before it ran, for whoever may read that database.
  def data_repair_copy
    repair = conversation.chat&.data_repairs&.find_by(id: params[:data_repair_id])
    return redirect_to(agent_chat_path(conversation), alert: "That copy is no longer in this chat.") unless repair

    copy = repair.copy_for(current_membership)
    return redirect_to(agent_chat_path(conversation), alert: copy.refusal) if copy.refusal

    response.headers["Cache-Control"] = "no-store"
    send_data copy.text, filename: copy.filename, type: "text/plain", disposition: "attachment"
  end

  # Fix it on a pull request Halon opened from this chat: the code change runs on its branch as whoever asked for it.
  def fix_pull_request
    notice = conversation.pull_request_notices.find_by(id: params[:notice_id])
    return redirect_to(agent_chat_path(conversation), alert: "That pull request is no longer in this chat.") unless notice

    blocked = PullRequestFollowing.fix!(notice, by: current_membership)
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

    redirect_to agent_chat_path(conversation), notice: "Halon is fixing #{notice.session.pull_request_label}."
  end

  # Asks the workspace admins for the pack a change in this chat was refused for, at most once a day.
  def ask_pack
    refusal = conversation.chat&.pack_refusals&.find_by(id: params[:pack_refusal_id])
    return redirect_to(agent_chat_path(conversation), alert: "That refusal is no longer in this chat.") unless refusal

    result = PackRequestService.ask!(refusal.pack_request, by: current_membership)
    redirect_to agent_chat_path(conversation), (result.ok ? :notice : :alert) => result.words
  end

  # Sends the value the person typed for a secret a tool call asked for, straight to the provider. The value is never
  # kept, and the parameter's name keeps it out of the logs.
  def fill_secret
    entry = conversation.chat&.secret_entries&.find_by(id: params[:secret_entry_id])
    return redirect_to(agent_chat_path(conversation), alert: SECRET_GONE) unless entry

    result = SecretEntryService.fill!(entry, value: params[:secret_value].to_s, by: current_membership)
    redirect_to agent_chat_path(conversation), (result.ok ? :notice : :alert) => result.words
  end

  # A credential a tool call made, read from the provider now for the person it was made for. Answered as JSON for the
  # dialog that shows it, and never cached.
  def reveal_secret
    response.headers["Cache-Control"] = "no-store"
    entry = conversation.chat&.secret_entries&.find_by(id: params[:secret_entry_id], kind: Chat::SecretEntry::KIND_REVEAL)
    return render(json: { error: SECRET_GONE }, status: :not_found) unless entry

    revealed = SecretEntryService.reveal(entry, by: current_membership)
    return render(json: { error: revealed.words }, status: :unprocessable_content) unless revealed.value

    render json: { value: revealed.value }
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

  # One that was asked for again is shown as the new request, never twice.
  def held_calls_shown
    chat = conversation.chat
    chat ? chat.held_calls.where.not(status: Chat::HeldCall::STATUS_ASKED_AGAIN).includes(:decided_by, approval: :approver) : []
  end

  def watches_shown
    chat = conversation.chat
    chat ? chat.watches.includes(:steps, :asker) : []
  end

  def plans_shown
    chat = conversation.chat
    chat ? chat.plans.includes(:steps, :approved_by, :undoes, :undo_plan, chat: :owner) : []
  end

  # The block answers with why it was refused, or nil, and the notice for when it went through.
  def decide_plan
    plan = conversation.chat&.plans&.find_by(id: params[:plan_id])
    return redirect_to(agent_chat_path(conversation), alert: "That plan is no longer in this chat.") unless plan

    blocked, done = yield plan
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

    redirect_to agent_chat_path(conversation), notice: done
  end

  def watch_updates_shown
    chat = conversation.chat
    chat ? chat.watch_updates.includes(:watch).reorder(:created_at) : []
  end

  def pull_request_notices_shown
    conversation.pull_request_notices.includes(:fix_by, session: :principal).order(:created_at)
  end

  def pack_refusals_shown
    chat = conversation.chat
    chat ? chat.pack_refusals.includes(pack_request: [ { requester: :user }, :role ]).order(:created_at) : []
  end

  def decide_mitigation
    mitigation = conversation.chat&.mitigations&.find_by(id: params[:mitigation_id])
    return redirect_to(agent_chat_path(conversation), alert: "That change is no longer in this chat.") unless mitigation

    blocked, done = yield mitigation
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

    redirect_to agent_chat_path(conversation), notice: done
  end

  def decide_held_call(done)
    held = conversation.chat&.held_calls&.find_by(id: params[:held_call_id])
    return redirect_to(agent_chat_path(conversation), alert: "That call is no longer in this chat.") unless held

    blocked = yield held
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

    redirect_to agent_chat_path(conversation), notice: done
  end

  def started_investigations
    conversation.investigations.seen.includes(:subject, :finding, :steps, chat: :charts).order(:created_at)
  end

  # Only a run this chat started opens over it. Any other opens nothing.
  def open_investigation
    id = params[Investigation::QUERY_PARAM]
    investigation = id.presence && conversation.investigations.seen.find_by(id: id)
    investigation && InvestigationDetailSerializer.one(investigation, file_path: ->(file) { agent_chat_investigation_file_path(conversation, investigation, file) })
  end

  def question = params[:question].to_s.strip

  def files_sent = Chat::Attachment.to_send!(workspace: current_workspace, member: current_membership, ids: params[:attachment_ids])

  # An open chat keeps the model it was started on. A new one gets the workspace's.
  def attachment_rules(chat)
    AgentChatAttachmentRulesSerializer.one(Chat::Attachment.rules_for(current_workspace, model_id: chat&.model_id, provider: chat&.model&.provider))
  end

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
      PROP_ENVIRONMENTS => reads_integrations? ? EnvironmentOptionSerializer.many(current_workspace.environment_entries) : [],
      PROP_SETUP_GUIDE => setup_guide
    }
  end

  def setup_guide
    guide = current_workspace.onboarding&.halon_guide(current_membership)
    guide && guide.merge(setupPath: onboarding_checklist_path)
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
end
