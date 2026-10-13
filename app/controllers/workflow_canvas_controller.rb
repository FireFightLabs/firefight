# A workflow's canvas: the version it shows (the draft, else the live one, else the one asked for in the address), its
# history with who changed what, Halon's suggestions and changes, the palette, and who asked an admin to publish it.
class WorkflowCanvasController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: :show

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
  PROPS = {
    "WORKFLOW" => PROP_WORKFLOW, "DOCUMENT" => PROP_DOCUMENT, "VERSIONS" => PROP_VERSIONS, "SUGGESTIONS" => PROP_SUGGESTIONS,
    "HALON_CHANGES" => PROP_HALON_CHANGES, "STEP_KINDS" => PROP_STEP_KINDS, "TRIGGER_KINDS" => PROP_TRIGGER_KINDS, "TOOLS" => PROP_TOOLS,
    "PUBLISH_REQUESTS" => PROP_PUBLISH_REQUESTS, "OTHER_WORKFLOWS" => PROP_OTHER_WORKFLOWS, "TIME_ZONES" => PROP_TIME_ZONES,
    "TEAMS" => PROP_TEAMS, "MY_PUBLISH_REQUEST" => PROP_MY_PUBLISH_REQUEST, "ACCESS" => PROP_ACCESS,
    "PLACES" => PROP_PLACES, "WATCH_READS" => PROP_WATCH_READS
  }.freeze
  # The address names an older version to look at by its id, and the view the canvas shows.
  VERSION_QUERY_PARAM = "version"
  VIEW_QUERY_PARAM = "view"
  VERSIONS_SHOWN = 50

  def show
    shown = workflow.shown_version(params[VERSION_QUERY_PARAM])
    suggestions = workflow.proposals.includes(:workflow, :source_run, source_chat: :owner).to_a
    render inertia: "halon/workflow", props: {
      PROP_WORKFLOW => WorkflowDetailSerializer.one(Workflow.with_run_counts.includes(:latest_run, :owner_team, :agent).find(workflow.id)),
      PROP_DOCUMENT => WorkflowDocumentSerializer.one(shown, facts: facts_for(Workflow::Version.all_steps(shown.steps)), workflow: workflow,
                                                             last_changes: shown.persisted? ? shown.last_changes : {}),
      PROP_VERSIONS => WorkflowVersionRowSerializer.many(workflow.versions.includes(:author, :published_by).newest_first.limit(VERSIONS_SHOWN)),
      PROP_SUGGESTIONS => WorkflowSuggestionSerializer.many(suggestions, document: (workflow.draft || workflow.live_version || workflow.empty_version).snapshot,
                                                                        facts: facts_for(suggestions.map { |suggestion| suggestion.payload["step"].to_h }),
                                                                        workflow: workflow),
      PROP_HALON_CHANGES => WorkflowHalonChangeSerializer.many(workflow.halon_changes(shown), workflow: workflow),
      PROP_STEP_KINDS => WorkflowStepKindSerializer.many(Workflow::StepKinds.offered, facts: Workflow::StepKinds::Facts.new(workspace: current_workspace)),
      PROP_TRIGGER_KINDS => WorkflowTriggerKindSerializer.many(Workflow::TriggerKinds.all),
      PROP_TOOLS => InertiaRails.defer { tools_offered },
      PROP_PUBLISH_REQUESTS => publish_requests,
      PROP_MY_PUBLISH_REQUEST => my_publish_request,
      PROP_TEAMS => teams,
      PROP_ACCESS => access,
      PROP_PLACES => InertiaRails.defer { RunbookPlaceSerializer.many(Chat::Tools::Choices.places(current_workspace, current_membership)) },
      PROP_WATCH_READS => InertiaRails.defer { RunbookWatchReadSerializer.many(Chat::Tools::Choices.reads) },
      PROP_OTHER_WORKFLOWS => Workflow.where(workspace: current_workspace).where.not(id: workflow.id).ordered.map { |other| { name: other.name, slug: other.slug } },
      PROP_TIME_ZONES => Workspace::FreezeWindows.time_zones
    }
  end

  private

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

  # Tools are only looked up when a step calls one, since building the list reads every connection's schemas.
  def facts_for(steps)
    calls_tool = steps.any? { |step| step["kind"] == Workflow::StepKinds::KIND_CALL_TOOL }
    calls_tool ? tool_facts : Workflow::StepKinds::Facts.new(workspace: current_workspace)
  end

  def tool_facts = @tool_facts ||= Workflow::StepKinds::Facts.new(workspace: current_workspace, tools: tool_choices)

  def tool_choices = @tool_choices ||= Chat::Tools::Choices.tools(current_workspace)

  # The tools a Call a tool step can call, once that kind can run.
  def tools_offered
    return [] unless Workflow::StepKinds.runnable?(Workflow::StepKinds::KIND_CALL_TOOL)

    WorkflowToolChoiceSerializer.many(tool_choices, workflow: workflow)
  end
end
