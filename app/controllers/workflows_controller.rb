# The workspace's workflows, under Halon: what each does and when it runs, its runs, the one offs that are done, and the
# library to start one from. Members build drafts, test them and run what is published. Publishing, or changing a live
# workflow, needs workflows.update, and granting the workflow's own identity what it needs needs permissions.create,
# so a member asks an admin instead.
class WorkflowsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: %i[index show], create: %i[create run test_run ask_publish],
                                                  update: %i[update publish enable disable repeat], delete: %i[destroy]

  include RequiresWorkflows

  before_action :set_workflow, except: %i[index create]

  TAB_QUERY = "tab".freeze
  TAB_WORKFLOWS = "workflows".freeze
  TAB_RUNS = "runs".freeze
  TAB_DONE = "done".freeze
  TABS = [ TAB_WORKFLOWS, TAB_RUNS, TAB_DONE ].freeze
  RUNS_SHOWN = 100
  SETTINGS = %i[name description owner_team_id cost_cap_cents runs_per_hour subject_key freeze_behaviour all_clear].freeze

  def index
    workflows = listed
    done, going = workflows.partition(&:done?)
    runs = paged(Workflow::Run.where(workspace: current_workspace))

    render inertia: "halon/workflows", props: {
      workflows: WorkflowRowSerializer.many(going),
      done: WorkflowRowSerializer.many(done),
      doneRuns: WorkflowRunRowSerializer.many(runs_of(done)),
      runs: WorkflowRunRowSerializer.many(runs.records),
      runsPage: runs.page,
      templates: templates,
      publishRequests: WorkflowPublishRequestSerializer.many(current_workspace_requests),
      timeZones: Workspace::FreezeWindows.time_zones
    }
  end

  def show
    render inertia: "halon/workflow", props: {
      workflow: WorkflowDetailSerializer.one(@workflow),
      runs: WorkflowRunRowSerializer.many((runs = paged(@workflow.runs)).records),
      runsPage: runs.page,
      myPublishRequest: my_publish_request,
      teams: teams,
      timeZones: Workspace::FreezeWindows.time_zones
    }
  end

  # A new draft from the library.
  def create
    workflow = Workflow::Library.create!(workspace: current_workspace, key: params[:template].to_s, params: template_params, by: current_membership)
    redirect_to workflow_path(workflow), notice: "#{workflow.name} was made as a draft."
  rescue Workflow::Library::Refused, Workflow::Edit::Refused, ActiveRecord::RecordInvalid => error
    redirect_to halon_workflows_path, alert: refusal_words(error)
  end

  def run
    run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: current_membership, inputs: inputs)
    redirect_to workflow_run_path(@workflow, run), notice: "#{@workflow.name} is running."
  rescue Workflow::Run::Refused => refused
    redirect_back fallback_location: workflow_path(@workflow), alert: refused.message
  end

  # A test run of the draft as the person testing: reads run for real and every change only shows what it would do,
  # unless they turned that step on.
  def test_run
    run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: current_membership, inputs: inputs,
                                                   test: true, real_step_keys: Array(params[:real_step_ids]))
    redirect_to workflow_run_path(@workflow, run), notice: "A test run of #{@workflow.name} started."
  rescue Workflow::Run::Refused => refused
    redirect_back fallback_location: workflow_path(@workflow), alert: refused.message
  end

  def publish
    draft = @workflow.draft
    return redirect_to(workflow_path(@workflow), alert: "#{@workflow.name} has no draft to publish.") unless draft
    return unless @workflow.missing_reach(draft).empty? || authorize_web!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)

    result = WorkflowPublishService.new(@workflow).publish!(draft, by: current_membership, revision: params[:revision].presence&.to_i || draft.revision)
    redirect_to workflow_path(@workflow), (result.ok ? :notice : :alert) => result.words
  end

  def ask_publish
    draft = @workflow.draft
    return redirect_to(workflow_path(@workflow), alert: "#{@workflow.name} has no draft to publish.") unless draft

    request = Workflow::PublishRequest.for!(current_membership, @workflow, draft)
    result = WorkflowPublishService.new(@workflow).ask!(request, by: current_membership)
    redirect_to workflow_path(@workflow), (result.ok ? :notice : :alert) => result.words
  end

  def update
    @workflow.update!(settings_params)
    redirect_to workflow_path(@workflow), notice: "#{@workflow.name} was updated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: workflow_path(@workflow), inertia: { errors: error.record.errors.to_hash }
  end

  def enable
    WorkflowPublishService.new(@workflow).switch!(on: true)
    redirect_back fallback_location: workflow_path(@workflow), notice: "#{@workflow.name} is on."
  end

  def disable
    WorkflowPublishService.new(@workflow).switch!(on: false)
    redirect_back fallback_location: workflow_path(@workflow), notice: "#{@workflow.name} is off."
  end

  # A one off that ran, made to repeat on a schedule: a draft with the new trigger, published like any change.
  def repeat
    schedule = params.permit(:repeat, :every, :at, :time_zone, :week_of_month, :weekday, days: []).to_h
    trigger = { Workflow::Trigger::KEY_KIND => Workflow::Trigger::KIND_SCHEDULE,
                Workflow::Trigger::KEY_INPUTS => Workflow::Trigger.inputs(@workflow.current_trigger) }.merge(schedule)
    problems = Workflow::Trigger.problems(trigger)
    return redirect_back(fallback_location: workflow_path(@workflow), alert: problems.first) if problems.any?

    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, payload: { trigger: trigger }, by: current_membership)
    redirect_to workflow_path(@workflow), notice: "#{@workflow.name} now has a draft that runs #{Workflow::Trigger.words(trigger).downcase_first}. Publish it to start."
  rescue Workflow::Edit::Refused => refused
    redirect_back fallback_location: workflow_path(@workflow), alert: refused.message
  end

  def destroy
    blocked = @workflow.deletion_blocked_reason
    return redirect_to(workflow_path(@workflow), alert: blocked) if blocked

    @workflow.agent&.destroy!
    @workflow.destroy!
    redirect_to halon_workflows_path, notice: "#{@workflow.name} was deleted."
  end

  private

  def set_workflow
    @workflow = current_workspace.workflows.with_run_counts.find(params[:id])
  end

  def listed
    current_workspace.workflows.with_run_counts.includes(:live_version, :draft_version, :latest_run, :owner_team).ordered.to_a
  end

  Paged = Data.define(:records, :page)

  # A page of runs, newest first, with whether there are more, so every run stays reachable.
  def paged(scope)
    number = [ params[:page].to_i, 1 ].max
    records = scope.includes(:workflow, :started_by).newest_first.offset((number - 1) * RUNS_SHOWN).limit(RUNS_SHOWN + 1).to_a
    Paged.new(records: records.first(RUNS_SHOWN), page: { number: number, more: records.size > RUNS_SHOWN })
  end

  def runs_of(workflows)
    return [] if workflows.empty?

    Workflow::Run.where(workflow_id: workflows.map(&:id)).includes(:workflow, :started_by).newest_first.limit(RUNS_SHOWN)
  end

  # Whoever may publish is shown what waits for them.
  def current_workspace_requests
    return [] unless current_membership.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE, current_workspace)

    Workflow::PublishRequest.waiting.where(workspace: current_workspace).includes(:workflow, :requester, :version).order(:requested_at)
  end

  def my_publish_request
    request = @workflow.publish_requests.find_by(requester: current_membership)
    draft = @workflow.draft
    blocked = request ? request.ask_blocked_reason(current_membership) : (draft ? nil : "#{@workflow.name} has no draft to publish.")
    { waiting: request&.waiting? || false, askBlockedReason: blocked }
  end

  def templates
    Workflow::Library::TEMPLATES.values.map { |template| { key: template.key, name: template.name, description: template.description } }
  end

  def teams
    type = current_workspace.catalog_types.find_by(system_key: CatalogType::SYSTEM_KEY_TEAM)
    type ? type.catalog_entries.active.order(:name).map { |team| { id: team.id, name: team.name } } : []
  end

  def template_params
    params.permit(Workflow::Library::PARAM_RESOURCE, Workflow::Library::PARAM_AT, Workflow::Library::PARAM_TIME_ZONE,
                  Workflow::Library::PARAM_CHANNEL, Workflow::Library::PARAM_REPLY_IN_CHAT, Workflow::Library::PARAM_DAYS => []).to_h
  end

  # Only the questions the live version or the draft asks, each a plain answer.
  def inputs
    asked = [ @workflow.live_version, @workflow.draft ].compact.flat_map { |version| Workflow::Trigger.input_keys(version.trigger) }.uniq
    params.fetch(:inputs, {}).permit(*asked).to_h
  end

  def settings_params
    given = params.permit(*SETTINGS).to_h
    given["cost_cap_cents"] = given["cost_cap_cents"].presence
    given["subject_key"] = given["subject_key"].to_s.strip.presence if given.key?("subject_key")
    given["owner_team_id"] = given["owner_team_id"].presence if given.key?("owner_team_id")
    given
  end

  def refusal_words(error) = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
end
