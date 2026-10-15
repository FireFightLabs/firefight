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
  # What Halon's browser saw in the open chat, each drawn under the step that took it.
  PROP_SCREENSHOTS = "screenshots"
  # What the person sent while the agent worked, which joins the answer at its next step.
  PROP_WAITING_MESSAGES = "waitingMessages"
  # What the composer takes, and whether the open chat's model reads images.
  PROP_ATTACHMENT_RULES = "attachmentRules"
  # Each time the open chat made room in the model's window, placed among the steps by when it happened.
  PROP_COMPACTIONS = "compactions"
  # Each time the open chat carried on with a backup model, placed among the steps the same way.
  PROP_MODEL_SWITCHES = "modelSwitches"
  # Calls an approval rule held in the open chat, from waiting for an approver to how they ended.
  PROP_HELD_CALLS = "heldCalls"
  # Changes Halon was refused in the open chat for want of a pack, each with Ask an admin.
  PROP_PACK_REFUSALS = "packRefusals"
  # Secrets a tool call in the open chat handed to the person who asked, to type or to reveal, never their values.
  PROP_SECRET_ENTRIES = "secretEntries"
  # What Halon watches for the open chat, going and ended, each a card that moves in place, and the lines the person may
  # need to act on (Chat::Watch::Update::KINDS_ON_THEIR_OWN), placed by when they were said.
  PROP_WATCHES = "watches"
  PROP_WATCH_UPDATES = "watchUpdates"
  # What Halon said about pull requests it opened from this chat that need attention, each with Fix it.
  PROP_PULL_REQUEST_NOTICES = "pullRequestNotices"
  # Code changes from this chat that reached their spending limit, each with Continue and Stop until someone decides.
  PROP_CODE_PAUSES = "codePauses"
  # Memories something contradicted in this chat, each asking the person which is right.
  PROP_MEMORY_QUESTIONS = "memoryQuestions"
  # The checks Halon handed to helpers in this chat, each drawn under the step that started it with the steps it took.
  PROP_HELPERS = "helpers"
  # Handbook edits Halon proposed in this chat, each asking the person to accept, edit or dismiss it.
  PROP_HANDBOOK_PROPOSALS = "handbookProposals"
  # Skills Halon proposed in this chat, each asking the person to accept, edit or dismiss it.
  PROP_SKILL_PROPOSALS = "skillProposals"
  # Setup's Meet Halon step, while an admin is on it: the question to start with, and whether Halon has answered.
  PROP_SETUP_GUIDE = "setupGuide"
  # Workflows Halon made in the open chat, each a card with Run now and Cancel, only where the workspace has workflows.
  PROP_WORKFLOWS = "workflows"
  # The plans Halon keeps in the open chat, each a checklist that moves as it works.
  PROP_PLANS = "plans"
  # Statements Halon ran that changed rows, with their counts, check and the copy kept of the rows.
  PROP_DATA_REPAIRS = "dataRepairs"
  # Changes customers feel that Halon made, undone when their time is up unless someone keeps them.
  PROP_MITIGATIONS = "mitigations"
  # Owners asked before Halon stopped something they started.
  PROP_OWNER_ASKS = "ownerAsks"
  # The models the open chat can switch to and the one it runs on, or nil when there is only one.
  PROP_CHAT_MODELS = "chatModels"
  # Halon's theory board while it troubleshoots in this chat, drawn under the step that last updated it.
  PROP_THEORIES = "theories"
  # Which chat the conversation props were read for, so a page switching chats shows a skeleton, never the last chat's.
  PROP_THREAD_FOR = "threadFor"
  PROPS = {
    "CONVERSATIONS" => PROP_CONVERSATIONS, "ARCHIVED_COUNT" => PROP_ARCHIVED_COUNT,
    "CONVERSATION" => PROP_CONVERSATION, "MESSAGES" => PROP_MESSAGES, "INCIDENTS" => PROP_INCIDENTS,
    "CONFIRMATIONS" => PROP_CONFIRMATIONS, "INTEGRATION_CARDS" => PROP_INTEGRATION_CARDS,
    "ENVIRONMENTS" => PROP_ENVIRONMENTS, "INVESTIGATIONS" => PROP_INVESTIGATIONS,
    "OPEN_INVESTIGATION" => PROP_OPEN_INVESTIGATION, "CHARTS" => PROP_CHARTS, "SCREENSHOTS" => PROP_SCREENSHOTS, "WAITING_MESSAGES" => PROP_WAITING_MESSAGES,
    "ATTACHMENT_RULES" => PROP_ATTACHMENT_RULES, "COMPACTIONS" => PROP_COMPACTIONS, "MODEL_SWITCHES" => PROP_MODEL_SWITCHES, "HELD_CALLS" => PROP_HELD_CALLS,
    "PACK_REFUSALS" => PROP_PACK_REFUSALS, "SECRET_ENTRIES" => PROP_SECRET_ENTRIES, "SETUP_GUIDE" => PROP_SETUP_GUIDE, "WATCHES" => PROP_WATCHES, "WATCH_UPDATES" => PROP_WATCH_UPDATES,
    "PULL_REQUEST_NOTICES" => PROP_PULL_REQUEST_NOTICES, "CODE_PAUSES" => PROP_CODE_PAUSES, "MEMORY_QUESTIONS" => PROP_MEMORY_QUESTIONS, "PLANS" => PROP_PLANS, "WORKFLOWS" => PROP_WORKFLOWS,
    "DATA_REPAIRS" => PROP_DATA_REPAIRS, "MITIGATIONS" => PROP_MITIGATIONS, "OWNER_ASKS" => PROP_OWNER_ASKS, "HELPERS" => PROP_HELPERS,
    "HANDBOOK_PROPOSALS" => PROP_HANDBOOK_PROPOSALS, "SKILL_PROPOSALS" => PROP_SKILL_PROPOSALS, "CHAT_MODELS" => PROP_CHAT_MODELS, "THEORIES" => PROP_THEORIES, "THREAD_FOR" => PROP_THREAD_FOR
  }.freeze
  # What the open chat's composer and model picker need, sent with the page so it shows at once.
  HEAD_PROPS = [ PROP_CONVERSATION, PROP_OPEN_INVESTIGATION, PROP_ATTACHMENT_RULES, PROP_SETUP_GUIDE, PROP_CHAT_MODELS ].freeze
  # Read for the same stretch of the chat as its messages, so scrolling up to older messages reads these again with them.
  WINDOWED_PROPS = [
    PROP_INVESTIGATIONS, PROP_CHARTS, PROP_SCREENSHOTS, PROP_COMPACTIONS, PROP_MODEL_SWITCHES, PROP_HELD_CALLS, PROP_PACK_REFUSALS,
    PROP_SECRET_ENTRIES, PROP_WATCHES, PROP_WATCH_UPDATES, PROP_PULL_REQUEST_NOTICES, PROP_CODE_PAUSES, PROP_MEMORY_QUESTIONS, PROP_PLANS, PROP_WORKFLOWS,
    PROP_DATA_REPAIRS, PROP_MITIGATIONS, PROP_OWNER_ASKS, PROP_HELPERS, PROP_HANDBOOK_PROPOSALS, PROP_SKILL_PROPOSALS, PROP_THEORIES
  ].freeze
  # The conversation itself, loaded in one request right after the page shows. Confirmations and waiting messages are
  # live whenever they were made, so they are always read whole.
  THREAD_PROPS = [ PROP_THREAD_FOR, PROP_MESSAGES, PROP_CONFIRMATIONS, PROP_WAITING_MESSAGES, *WINDOWED_PROPS ].freeze
  # What a question changes, the only props read back after one: whether Halon works, the message saved, or the one
  # waiting for Halon's next step.
  ASKED_PROPS = [ PROP_CONVERSATION, PROP_THREAD_FOR, PROP_MESSAGES, PROP_WAITING_MESSAGES ].freeze
  # What answering confirmations changes: the cards, the steps that waited on them, whether Halon goes on, and what an
  # answer starts (a change's time until it is undone, an owner asked, the rows a statement may change).
  DECIDED_PROPS = [ PROP_CONVERSATION, PROP_MESSAGES, PROP_CONFIRMATIONS, PROP_DATA_REPAIRS, PROP_MITIGATIONS, PROP_OWNER_ASKS ].freeze
  THREAD_GROUP = "thread"
  # Older messages load a page at a time as the person scrolls up, each page asked for by the oldest message shown.
  MESSAGES_BEFORE_PARAM = "before"
  # The oldest message the open chat shows, sent with each visit to it, so what a visit reloads keeps that stretch of the
  # chat rather than going back to the newest page.
  LOADED_FROM_HEADER = "X-Chat-Loaded-From"
  # The newest active incidents, the ones people ask about.
  MENTIONABLE = 20
  NOTHING_ASKED = "Say something first."
  SECRET_GONE = "That secret is no longer in this chat."
  CHAT_DELETED = "Chat deleted."

  include ServesChatAttachment
  include PlatformText

  # Asking spends money, so it needs the same permission as starting an investigation.
  authorizes Ability::Action::RESOURCE_CHATS, read: %i[index show search investigation_file screenshot investigation_screenshot data_repair_copy],
                                             update: %i[update ask_pack fill_secret reveal_secret], delete: %i[destroy]
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[create ask confirm stop run_held_call dismiss_held_call ask_held_call_again stop_watch fix_pull_request
                                                                schedule_plan cancel_plan retry_plan undo_plan keep_mitigation extend_mitigation
                                                                undo_mitigation]
  authorizes Ability::Action::RESOURCE_INCIDENTS, read: %i[incidents]
  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: %i[press_workflow]

  include RequiresAgent
  before_action :require_agent!
  # Setup's Meet Halon step is a chat here.
  skip_before_action :continue_setup

  # Sent empty so a partial visit here clears the open chat instead of keeping the last one.
  def index
    render inertia: "agent/index", props: base_props.merge(
      PROP_CONVERSATION => nil, PROP_MESSAGES => [], PROP_CONFIRMATIONS => [], PROP_INVESTIGATIONS => [], PROP_OPEN_INVESTIGATION => nil,
      PROP_CHARTS => [], PROP_SCREENSHOTS => [], PROP_WAITING_MESSAGES => [], PROP_ATTACHMENT_RULES => attachment_rules(nil), PROP_COMPACTIONS => [],
      PROP_MODEL_SWITCHES => [], PROP_HELD_CALLS => [], PROP_PACK_REFUSALS => [], PROP_SECRET_ENTRIES => [], PROP_WATCHES => [], PROP_WATCH_UPDATES => [],
      PROP_PULL_REQUEST_NOTICES => [], PROP_CODE_PAUSES => [], PROP_MEMORY_QUESTIONS => [], PROP_PLANS => [], PROP_WORKFLOWS => [], PROP_DATA_REPAIRS => [],
      PROP_MITIGATIONS => [],
      PROP_OWNER_ASKS => [], PROP_HELPERS => [], PROP_HANDBOOK_PROPOSALS => [], PROP_SKILL_PROPOSALS => [], PROP_CHAT_MODELS => chat_models(nil), PROP_THEORIES => [],
      PROP_THREAD_FOR => nil
    )
  end

  # The page shows at once with what its composer needs, and the conversation follows as one deferred group. Its
  # messages are the newest page, older ones arrive a page at a time as the person scrolls up, and everything placed among
  # them is read for the same stretch (Chat::Window).
  def show
    render inertia: "agent/index", props: base_props.merge(
      PROP_CONVERSATION => -> { AgentChatSerializer.one(conversation, opened: true, asked_in_url: asked_in_url, platform_texts: listed_in_platform([ conversation ])) },
      PROP_OPEN_INVESTIGATION => -> { open_investigation },
      PROP_ATTACHMENT_RULES => -> { attachment_rules(conversation.chat, picked: conversation.picked_model_choice) },
      PROP_CHAT_MODELS => -> { chat_models(conversation) },
      PROP_THREAD_FOR => in_thread { conversation.id },
      PROP_MESSAGES => InertiaRails.scroll(window.scroll_metadata(MESSAGES_BEFORE_PARAM), defer: opening?, group: THREAD_GROUP, match_on: "id") { messages_shown },
      PROP_CONFIRMATIONS => in_thread { AgentChatConfirmationSerializer.many(on_chat(&:awaiting_decision), screenshot_path: screenshot_path) },
      PROP_WAITING_MESSAGES => in_thread { waiting_shown },
      PROP_INVESTIGATIONS => in_thread { InvestigationCardSerializer.many(window.stepped(started_investigations)) },
      PROP_CHARTS => in_thread { ChatChartSerializer.many(on_chat { |chat| window.stepped(chat.charts) }) },
      PROP_SCREENSHOTS => in_thread { ChatScreenshotSerializer.many(on_chat { |chat| window.stepped(chat.screenshots) }, screenshot_path: screenshot_path) },
      PROP_COMPACTIONS => in_thread { ChatCompactionSerializer.many(on_chat { |chat| window.placed(chat.compactions) }) },
      PROP_MODEL_SWITCHES => in_thread { ChatModelSwitchSerializer.many(on_chat { |chat| window.placed(chat.model_switches) }) },
      PROP_HELD_CALLS => in_thread { AgentChatHeldCallSerializer.many(held_calls_shown, member: current_membership) },
      PROP_PACK_REFUSALS => in_thread { AgentChatPackRefusalSerializer.many(pack_refusals_shown, member: current_membership) },
      PROP_SECRET_ENTRIES => in_thread { AgentChatSecretEntrySerializer.many(secret_entries_shown, member: current_membership) },
      PROP_WATCHES => in_thread { AgentChatWatchSerializer.many(watches_shown, member: current_membership) },
      PROP_WATCH_UPDATES => in_thread { AgentChatWatchUpdateSerializer.many(watch_updates_shown) },
      PROP_PULL_REQUEST_NOTICES => in_thread { AgentChatPullRequestNoticeSerializer.many(pull_request_notices_shown, member: current_membership) },
      PROP_CODE_PAUSES => in_thread { AgentChatCodePauseSerializer.many(code_pauses_shown, member: current_membership) },
      PROP_MEMORY_QUESTIONS => in_thread do
        AgentChatMemoryQuestionSerializer.many(window.placed(conversation.memory_posts.order(:created_at)), member: current_membership)
      end,
      PROP_PLANS => in_thread { AgentChatPlanSerializer.many(plans_shown, member: current_membership) },
      PROP_WORKFLOWS => in_thread { AgentChatWorkflowSerializer.many(workflows_shown, member: current_membership) },
      PROP_DATA_REPAIRS => in_thread do
        AgentChatDataRepairSerializer.many(on_chat { |chat| window.placed(chat.data_repairs.where(status: Chat::DataRepair::STATUS_RAN), Chat::DataRepair.placed_at) })
      end,
      PROP_MITIGATIONS => in_thread do
        AgentChatMitigationSerializer.many(on_chat { |chat| window.placed(chat.mitigations.shown, Chat::Mitigation.placed_at) }, member: current_membership)
      end,
      PROP_OWNER_ASKS => in_thread { AgentChatOwnerAskSerializer.many(on_chat { |chat| window.placed(chat.owner_asks.shown, Chat::OwnerAsk.placed_at) }) },
      PROP_HELPERS => in_thread { AgentChatHelperSerializer.many(on_chat { |chat| window.stepped(chat.helpers.includes(:workspace, :own_chat)) }) },
      PROP_HANDBOOK_PROPOSALS => in_thread do
        HandbookProposalSerializer.many(window.placed(conversation.handbook_proposals.includes(:instruction, :result, :decided_by).order(:created_at)))
      end,
      PROP_SKILL_PROPOSALS => in_thread { HalonSkillProposalSerializer.many(skill_proposals_shown) },
      PROP_THEORIES => in_thread { ChatTheorySerializer.many(on_chat { |chat| window.stepped(chat.theories) }) }
    )
  end

  # A file that went with a note to a run this chat started, for whoever may read the chat and so the run.
  def investigation_file
    investigation = conversation.investigations.seen.find(params[:investigation_id])
    send_chat_attachment(investigation.note_file(params[:file_id]))
  end

  # A page Halon's browser saw in this chat, for whoever may read the chat.
  def screenshot
    chat = conversation.chat
    raise ActiveRecord::RecordNotFound unless chat

    send_chat_attachment(chat.screenshots.find(params[:screenshot_id]))
  end

  # A page the browser saw in a run this chat started, for whoever may read the chat and so the run.
  def investigation_screenshot
    investigation = conversation.investigations.seen.find(params[:investigation_id])
    send_chat_attachment(investigation.screenshot(params[:screenshot_id]))
  end

  def search
    found = Conversation.search_for(current_membership, params[:q], shown: method(:platform_texts))
    render json: AgentChatSerializer.many(found, platform_texts: listed_in_platform(found))
  end

  def incidents
    render json: AgentChatIncidentSerializer.many(mentionable_incidents.search(params[:q].to_s.strip))
  end

  # A model picked before the first question goes with it.
  def create
    files = files_sent
    return redirect_to(agent_chats_path, alert: NOTHING_ASKED) if question.blank? && files.empty?

    blocked = picked_model && Conversation::ModelMenu.for(current_workspace).blocked_reason(picked_model)
    return redirect_to(agent_chats_path, alert: blocked) if blocked

    chat = Conversation::Asking.start_personal(workspace: current_workspace, member: current_membership, question: question, files: files,
                                               model: picked_model)
    redirect_to agent_chat_path(chat)
  rescue Chat::Attachment::Refused => refused
    redirect_to agent_chats_path, alert: refused.message
  end

  def ask
    blocked = conversation.ask_blocked_reason
    return redirect_to(agent_chat_path(conversation), alert: blocked) if blocked

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
    redirect_to agent_chat_path(conversation), notice: Conversation::STOPPING
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
  # Run now or Cancel on a workflow Halon made in this chat.
  def press_workflow
    workflow = chat_workflows.find_by(id: params[:workflow_id])
    return redirect_to(agent_chat_path(conversation), alert: "That workflow is no longer in this chat.") unless workflow

    result = Conversation::Workflows.press!(workflow, params[:press].to_s, by: current_membership)
    redirect_to agent_chat_path(conversation), (result.ok ? :notice : :alert) => result.words
  end

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
    return choose_model if params.key?(:model)
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

  def in_thread(&block) = opening? ? InertiaRails.defer(group: THREAD_GROUP, &block) : block

  # A page that already shows this chat names its oldest message, and a change made from it redirects back as a whole
  # visit, which would blank the conversation on screen if it were deferred. Only a chat being opened defers it.
  def opening? = request.headers[LOADED_FROM_HEADER].blank?

  # What the chat's record holds, or nothing for a conversation nobody has asked anything in yet.
  def on_chat
    chat = conversation.chat
    chat ? yield(chat) : []
  end

  def window
    @window ||= Chat::Window.new(conversation.chat, before: params[MESSAGES_BEFORE_PARAM], from: request.headers[LOADED_FROM_HEADER])
  end

  # Newest first, so Inertia's next page is the older one and is added after what the page holds.
  def messages_shown
    messages = window.messages.includes(:attached_files, :ruby_llm_usages, ruby_llm_tool_calls: :result).to_a.reverse
    asked = messages.select { |message| message.role == Chat::Message::ROLE_USER }
    AgentChatMessageSerializer.many(messages, member: current_membership, platform_texts: said_in_platform(asked))
  end

  def waiting_shown
    waiting = on_chat { |chat| chat.queued_messages.waiting.includes(:attached_files).to_a }
    AgentChatWaitingMessageSerializer.many(waiting, platform_texts: said_in_platform(waiting))
  end

  # One that was asked for again is shown as the new request, never twice.
  def held_calls_shown
    on_chat do |chat|
      shown = chat.held_calls.where.not(status: Chat::HeldCall::STATUS_ASKED_AGAIN).joins(:approval).includes(:decided_by, approval: :approver)
      window.placed(shown, Chat::HeldCall.placed_at)
    end
  end

  def secret_entries_shown = on_chat { |chat| window.placed(chat.secret_entries.includes(:requester, :done_by, tool: :integration)) }

  # One still going is always read, since the strip above the composer shows it however far back it started.
  def watches_shown
    on_chat { |chat| window.placed(chat.watches).or(chat.watches.active).includes(:steps, :asker, :updates) }
  end

  # The workflows made in this chat, none where the workspace has no workflows.
  def chat_workflows
    return Workflow.none unless FeatureFlags.enabled?(current_workspace, FeatureFlags::WORKFLOWS)

    conversation.workflows.with_run_counts
  end

  # The skills Halon proposed in the stretch of the chat on screen, none where the workspace keeps no skills of its own.
  def skill_proposals_shown
    return [] unless Chat::CustomSkill.enabled_for?(current_workspace)

    window.placed(conversation.skill_proposals.includes(:decided_by, :parent_version, custom_skill: :live_version).order(:created_at))
  end

  # Those made in the stretch of the chat on screen, each placed after the turn that made it.
  def workflows_shown = window.placed(chat_workflows, Workflow.arel_table[:created_at]).includes(:live_version, :draft_version, :created_by).order(:created_at).to_a

  def plans_shown
    on_chat { |chat| window.placed(chat.plans, Chat::Plan.placed_at).includes(:steps, :approved_by, :undoes, :undo_plan, chat: :owner) }
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
    on_chat { |chat| window.placed(chat.watch_updates.on_their_own.includes(:watch).reorder(:created_at)) }
  end

  def pull_request_notices_shown
    window.placed(conversation.pull_request_notices.includes(:fix_by, session: :principal).order(:created_at))
  end

  # One still waiting for Continue or Stop is always read, like a confirmation, since the fix waits on it however far back
  # it paused. A decided one sits where it paused, read for the stretch shown.
  def code_pauses_shown
    pauses = conversation.code_pauses
    window.placed(pauses).or(pauses.where(status: CodeAgentSession::Pause::STATUS_OFFERED)).includes(:decided_by, session: :principal).order(:created_at)
  end

  def pack_refusals_shown
    on_chat { |chat| window.placed(chat.pack_refusals.includes(pack_request: [ { requester: :user }, :role ]).order(:created_at)) }
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
    investigation && InvestigationDetailSerializer.one(investigation, file_path: ->(file) { agent_chat_investigation_file_path(conversation, investigation, file) },
                                                                    screenshot_path: ->(shot) { agent_chat_investigation_screenshot_path(conversation, investigation, shot) },
                                                                    platform_texts: investigation_platform_texts(investigation))
  end

  def question = params[:question].to_s.strip

  def files_sent = Chat::Attachment.to_send!(workspace: current_workspace, member: current_membership, ids: params[:attachment_ids])

  # An open chat keeps the model it was started on, or the one the person picked. A new one gets the workspace's.
  def attachment_rules(chat, picked: nil)
    model_id, provider = picked ? [ picked.model, picked.provider ] : [ chat&.model_id, chat&.model&.provider ]
    AgentChatAttachmentRulesSerializer.one(Chat::Attachment.rules_for(current_workspace, model_id: model_id, provider: provider))
  end

  def picked_model = params[:model].presence&.to_s

  # A new chat starts on the workspace's main model until the person picks another.
  def chat_models(conversation)
    menu = conversation ? conversation.model_menu : Conversation::ModelMenu.for(current_workspace)
    return nil unless menu.offers_choice?

    ChatModelMenuSerializer.one(menu, selected: menu.current(conversation&.chosen_model))
  end

  # Takes effect from the next question. A turn already running finishes on the model it started with.
  def choose_model
    model = params[:model].to_s
    menu = conversation.model_menu
    blocked = conversation.model_blocked_reason(model, menu: menu)
    return redirect_back_or_to(agent_chat_path(conversation), alert: blocked) if blocked

    conversation.choose_model!(model, menu: menu)
    redirect_back_or_to agent_chat_path(conversation), notice: "This chat now uses #{menu.label_for(model)}."
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

  def asked_in_url
    WorkspaceAdapter.for(current_workspace).channel_url(channel_id: conversation.channel_id) if conversation.direct?
  end

  def screenshot_path = ->(shot) { agent_chat_screenshot_path(conversation, shot) }

  def base_props
    {
      PROP_CONVERSATIONS => InertiaRails.scroll(chat_page_metadata) { AgentChatSerializer.many(chat_page, platform_texts: listed_in_platform(chat_page)) },
      PROP_ARCHIVED_COUNT => -> { own_chats.archived.count },
      PROP_INCIDENTS => -> { AgentChatIncidentSerializer.many(mentionable_incidents) },
      # What an integrations card draws, read fresh on every visit, so returning from connecting shows it connected.
      PROP_INTEGRATION_CARDS => -> { reads_integrations? ? IntegrationCardSerializer.many(IntegrationProvider.cards_for(current_workspace)) : [] },
      PROP_ENVIRONMENTS => -> { reads_integrations? ? EnvironmentOptionSerializer.many(current_workspace.environment_entries) : [] },
      PROP_SETUP_GUIDE => -> { setup_guide }
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
    @chat_page_rows ||= own_chats.includes(chat: [ :last_readable_message, :first_question ]).in_reading_order
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

  def own_chats = current_workspace.conversations.own_for(current_membership)

  # What the person said in a chat asked in the platform, in the platform's own markup, as the platform shows it.
  def said_in_platform(said)
    platform_texts(said.filter_map { |message| message.as_written || (message.content if conversation.said_in_platform_markup?) })
  end

  def listed_in_platform(chats) = platform_texts(chats.flat_map { |chat| [ chat.title_question, chat.preview_question ] })
end
