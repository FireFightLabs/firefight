# A workflow's canvas: the version it shows (the draft, else the live one, else the one asked for in the address), its
# history with who changed what, Halon's suggestions and changes, the palette, and who asked an admin to publish it.
class WorkflowCanvasController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: :show
  around_action :holding_reads, only: :show

  # Shared with the page through lib/typescript_constants.rb, since partial reloads ask for props by name.
  PROP_WORKFLOW = "workflow"
  PROP_DOCUMENT = "document"
  PROP_VERSIONS = "versions"
  PROP_SUGGESTIONS = "suggestions"
  PROP_HALON_CHANGES = "halonChanges"
  PROP_STEP_KINDS = "stepKinds"
  PROP_TRIGGER_KINDS = "triggerKinds"
  PROP_TOOLS = "tools"
  PROP_PUBLISH_REQUESTS = "publishRequests"
  PROP_OTHER_WORKFLOWS = "otherWorkflows"
  PROP_TIME_ZONES = "timeZones"
  # The owning teams a workflow's settings offer, and where the person stands on asking an admin to publish it.
  PROP_TEAMS = "teams"
  PROP_MY_PUBLISH_REQUEST = "myPublishRequest"
  # What the person may do here, as the gateway answers: build the draft (workflows.create, which members hold) and
  # manage the workflow, publishing it, its settings, switching it on or off and deleting it (workflows.update).
  PROP_ACCESS = "workflowAccess"
  # What a step's settings pick from: things on the map, and what a Watch step can read of them. Both deferred.
  PROP_PLACES = "places"
  PROP_WATCH_READS = "watchReads"
  PROP_RUNS = "runs"
  PROP_RUN = "run"
  PROP_LAST_RUN = "lastRun"
  # The person's chat with Halon beside this canvas, what was said in it, the checks Halon handed to helpers there, whether
  # something in it waits on them, and why they cannot ask Halon here, if they cannot.
  PROP_CHAT = "chat"
  PROP_CHAT_MESSAGES = "chatMessages"
  PROP_HELPERS = "helpers"
  # The charts Halon drew in that chat, set in its answers where it placed them.
  PROP_CHARTS = "charts"
  PROP_CHAT_WAITING = "chatWaiting"
  PROP_CHAT_UNAVAILABLE = "chatUnavailable"
  # When the page's props were read, which its live connection names so it is told only what changed since
  # (WorkflowChannel).
  PROP_LIVE_READ_AT = "liveReadAt"
  PROPS = {
    "WORKFLOW" => PROP_WORKFLOW, "DOCUMENT" => PROP_DOCUMENT, "VERSIONS" => PROP_VERSIONS, "SUGGESTIONS" => PROP_SUGGESTIONS,
    "HALON_CHANGES" => PROP_HALON_CHANGES, "STEP_KINDS" => PROP_STEP_KINDS, "TRIGGER_KINDS" => PROP_TRIGGER_KINDS, "TOOLS" => PROP_TOOLS,
    "PUBLISH_REQUESTS" => PROP_PUBLISH_REQUESTS, "OTHER_WORKFLOWS" => PROP_OTHER_WORKFLOWS, "TIME_ZONES" => PROP_TIME_ZONES,
    "TEAMS" => PROP_TEAMS, "MY_PUBLISH_REQUEST" => PROP_MY_PUBLISH_REQUEST, "ACCESS" => PROP_ACCESS,
    "PLACES" => PROP_PLACES, "WATCH_READS" => PROP_WATCH_READS,
    "RUNS" => PROP_RUNS, "RUN" => PROP_RUN, "LAST_RUN" => PROP_LAST_RUN, "CHAT" => PROP_CHAT, "CHAT_MESSAGES" => PROP_CHAT_MESSAGES,
    "HELPERS" => PROP_HELPERS, "CHARTS" => PROP_CHARTS, "CHAT_WAITING" => PROP_CHAT_WAITING, "CHAT_UNAVAILABLE" => PROP_CHAT_UNAVAILABLE,
    "LIVE_READ_AT" => PROP_LIVE_READ_AT
  }.freeze
  # The address names an older version to look at by its id, and the view the canvas shows.
  VERSION_QUERY_PARAM = "version"
  VIEW_QUERY_PARAM = "view"
  # The address names a run to show on the canvas by its id.
  RUN_QUERY_PARAM = Workflow::Links::RUN_PARAM
  RUNS_SHOWN = 50
  VERSIONS_SHOWN = 50
  # What asking Halon beside the canvas changes, the only props read back after a question or a stop.
  CHAT_PROPS = [ PROP_CHAT, PROP_CHAT_MESSAGES, PROP_HELPERS, PROP_CHARTS, PROP_CHAT_WAITING ].freeze

  # Each prop is worked out only when the visit asks for it, so asking Halon beside the canvas reads back the chat alone.
  def show
    Workflow::LiveDelivery.watching(workflow.id) unless request.inertia_partial?
    read_at = Time.current.to_f
    render inertia: "halon/workflow", props: {
      PROP_LIVE_READ_AT => -> { read_at },
      PROP_WORKFLOW => -> { WorkflowDetailSerializer.one(current_workspace.workflows.with_run_counts.includes(:latest_run, :owner_team, :agent).find(workflow.id)) },
      PROP_DOCUMENT => -> { document },
      PROP_RUNS => -> { WorkflowRunRowSerializer.many(workflow.runs.where(parent_run_id: nil).includes(:version, :started_by).newest_first.limit(RUNS_SHOWN)) },
      PROP_RUN => -> { shown_run && WorkflowRunDetailSerializer.one(shown_run, member: current_membership) },
      PROP_LAST_RUN => -> { last_run(shown) && WorkflowRunStatesSerializer.one(last_run(shown)) },
      PROP_VERSIONS => -> { WorkflowVersionRowSerializer.many(workflow.versions.includes(:author, :published_by).newest_first.limit(VERSIONS_SHOWN)) },
      PROP_SUGGESTIONS => -> { suggestions_shown },
      PROP_HALON_CHANGES => -> { WorkflowHalonChangeSerializer.many(workflow.halon_changes(shown), workflow: workflow) },
      PROP_STEP_KINDS => -> { WorkflowStepKindSerializer.many(Workflow::StepKinds.offered, facts: step_facts) },
      PROP_TRIGGER_KINDS => -> { WorkflowTriggerKindSerializer.many(Workflow::TriggerKinds.all, facts: step_facts) },
      PROP_TOOLS => InertiaRails.defer { tools_offered },
      PROP_PUBLISH_REQUESTS => -> { publish_requests },
      PROP_MY_PUBLISH_REQUEST => -> { my_publish_request },
      PROP_TEAMS => -> { teams },
      PROP_ACCESS => -> { access },
      PROP_PLACES => InertiaRails.defer { RunbookPlaceSerializer.many(Chat::Tools::Choices.places(current_workspace, current_membership)) },
      PROP_WATCH_READS => InertiaRails.defer { RunbookWatchReadSerializer.many(Chat::Tools::Choices.reads) },
      PROP_OTHER_WORKFLOWS => -> { Workflow.where(workspace: current_workspace).where.not(id: workflow.id).ordered.map { |other| { name: other.name, slug: other.slug } } },
      PROP_TIME_ZONES => -> { Workspace::FreezeWindows.time_zones }
    }.merge(chat_props)
  end

  private

  # The header, the steps and the tools list ask the same of the workspace's connections, such as what a step reaches,
  # so a visit works each out once rather than once a prop (Workspace::HeldReads).
  def holding_reads
    current_workspace.hold_reads!
    yield
  ensure
    current_workspace.release_reads!
  end

  # Read through the workspace so every prop shares its one copy, and the connections' tools a step's reach and problems
  # read are read once a visit rather than once for each copy of the workspace.
  def workflow
    @workflow ||= current_workspace.workflows.find(params[:id])
  end

  def shown_run
    return @shown_run if defined?(@shown_run)

    @shown_run = params[RUN_QUERY_PARAM].presence && workflow.runs.includes(steps: :chat).find_by(id: params[RUN_QUERY_PARAM])
  end

  def shown
    @shown ||= shown_run ? run_version(shown_run) : workflow.shown_version(params[VERSION_QUERY_PARAM])
  end

  def document
    WorkflowDocumentSerializer.one(shown, facts: step_facts, workflow: workflow,
                                          last_changes: shown_run || !shown.persisted? ? {} : shown.last_changes, pins: shown.pins,
                                          read_only: shown_run.present?)
  end

  def suggestions_shown
    suggestions = workflow.proposals.includes(:workflow, :source_run, source_chat: :owner).to_a
    WorkflowSuggestionSerializer.many(suggestions, document: (workflow.draft || workflow.live_version || workflow.empty_version).snapshot,
                                                   facts: step_facts,
                                                   workflow: workflow)
  end

  def chat_props
    {
      PROP_CHAT => -> { beside_chat && AgentChatSerializer.one(beside_chat, opened: true) },
      PROP_CHAT_MESSAGES => -> { AgentChatMessageSerializer.many(beside_messages, member: current_membership, platform_texts: {}) },
      PROP_HELPERS => -> { AgentChatHelperSerializer.many(beside_record&.helpers&.includes(:workspace, :own_chat) || []) },
      PROP_CHARTS => -> { ChatChartSerializer.many(beside_record&.charts || []) },
      PROP_CHAT_WAITING => -> { beside_record.present? && beside_record.awaiting_decision.any? },
      PROP_CHAT_UNAVAILABLE => -> { Conversation.asking_blocked_reason(current_membership) }
    }
  end

  def beside_chat
    return @beside_chat if defined?(@beside_chat)

    @beside_chat = Conversation.beside(workflow, current_membership)
  end

  def beside_record = beside_chat&.chat

  def beside_messages
    record = beside_record
    record ? record.readable_messages.includes(:attached_files, :ruby_llm_usages, ruby_llm_tool_calls: :result).to_a : []
  end

  # Whoever may publish is shown the members waiting on it.
  def publish_requests
    return [] unless current_membership.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE, current_workspace)

    WorkflowPublishRequestSerializer.many(workflow.publish_requests.waiting.includes(:workflow, :requester, :version).order(:requested_at))
  end

  def my_publish_request
    request = workflow.publish_requests.find_by(requester: current_membership)
    blocked = request ? request.ask_blocked_reason(current_membership) : (workflow.draft ? nil : "#{workflow.name} has no draft to publish.")
    { waiting: request&.waiting? || false, askBlockedReason: blocked }
  end

  def access
    { build: current_membership.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE, current_workspace),
      manage: current_membership.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE, current_workspace) }
  end

  def teams
    type = current_workspace.catalog_types.find_by(system_key: CatalogType::SYSTEM_KEY_TEAM)
    type ? type.catalog_entries.active.order(:name).map { |team| { id: team.id, name: team.name } } : []
  end

  # What a run ran, drawn as a version of its own: its copy when it ran less than its version or a draft that changed
  # since, else its version.
  def run_version(run)
    version = run.version
    return version unless run.snapshot.present?

    Workflow::Version.new(workflow: workflow, number: version.number, status: version.status, revision: version.revision,
                          author_kind: version.author_kind, author: version.author, **run.snapshot.slice(*Workflow::Version::CONTENT).symbolize_keys)
  end

  # The newest run of the version shown, whose states Last run lays over the steps.
  def last_run(version)
    return unless version.persisted?

    @last_run ||= workflow.runs.where(version: version, parent_run_id: nil).includes(:steps).newest_first.first
  end

  # What a kind's lambdas read of the workspace. The tools list stays out, since no node, kind or suggestion reads it
  # and building it reads every connection's schemas, which every poll of the canvas would pay for.
  def step_facts = @step_facts ||= Workflow::StepKinds::Facts.new(workspace: current_workspace)

  def tool_choices = @tool_choices ||= Chat::Tools::Choices.tools(current_workspace)

  # The tools a Call a tool step can call, once that kind can run.
  def tools_offered
    return [] unless Workflow::StepKinds.runnable?(Workflow::StepKinds::KIND_CALL_TOOL)

    WorkflowToolChoiceSerializer.many(tool_choices, workflow: workflow)
  end
end
