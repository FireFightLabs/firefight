# The workspace's workflows, under Halon: what each does and when it runs, its runs, the one offs that are done, and
# Firefight's library to start one from, with import and export (HalonWorkflowLibraryController answers its actions). Members build drafts, test them and run what is published. Publishing, or changing a live
# workflow, needs workflows.update, and granting the workflow's own identity what it needs needs permissions.create,
# so a member asks an admin instead.
class WorkflowsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: %i[index], create: %i[create run ask_publish],
                                                  update: %i[update publish enable disable repeat], delete: %i[destroy]

  include RequiresWorkflows

  before_action :set_workflow, except: %i[index create]

  TAB_QUERY = "tab".freeze
  TAB_WORKFLOWS = "workflows".freeze
  TAB_RUNS = "runs".freeze
  TAB_DONE = "done".freeze
  TAB_LIBRARY = "library".freeze
  TABS = [ TAB_WORKFLOWS, TAB_RUNS, TAB_DONE, TAB_LIBRARY ].freeze
  RUNS_SHOWN = 100

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
      timeZones: Workspace::FreezeWindows.time_zones,
      libraryItems: HalonLibraryWorkflowSerializer.many(Workflow::Library.all, used: used_by_item, workspace: current_workspace),
      libraryWorkflows: HalonLibraryWorkflowUseSerializer.many(current_workspace.workflows.includes(:live_version).ordered.to_a),
      canCreate: current_membership.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE, current_workspace)
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
    redirect_to workflow_path(@workflow, WorkflowCanvasController::RUN_QUERY_PARAM => run.id), notice: "#{@workflow.name} is running."
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
    @workflow.update_settings!(params.permit(*Workflow::Settings::KEYS).to_h)
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

    @workflow.destroy_with_agent!
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
    records = scope.includes(:workflow, :started_by, :version).newest_first.offset((number - 1) * RUNS_SHOWN).limit(RUNS_SHOWN + 1).to_a
    Paged.new(records: records.first(RUNS_SHOWN), page: { number: number, more: records.size > RUNS_SHOWN })
  end

  # The workspace's workflows made from each library item, by key, so the Library tab never asks per row.
  def used_by_item
    current_workspace.workflows.where.not(library_key: nil).order(:name).pluck(:library_key, :name).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def runs_of(workflows)
    return [] if workflows.empty?

    Workflow::Run.where(workflow_id: workflows.map(&:id)).includes(:workflow, :started_by, :version).newest_first.limit(RUNS_SHOWN)
  end

  # Whoever may publish is shown what waits for them.
  def current_workspace_requests
    return [] unless current_membership.may?(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE, current_workspace)

    Workflow::PublishRequest.waiting.where(workspace: current_workspace).includes(:workflow, :requester, :version).order(:requested_at)
  end

  def templates
    Workflow::Library::TEMPLATES.values.map { |template| { key: template.key, name: template.name, description: template.description } }
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

  def refusal_words(error) = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
end
