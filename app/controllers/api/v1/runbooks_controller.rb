class Api::V1::RunbooksController < Api::V1::ApiController
  include FreeFormParams

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_runbook, only: %i[show update destroy]

  def index
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ)
    @runbooks = current_workspace.runbooks.active.ordered.includes(:runbook_steps)
  end

  def show
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ)
  end

  # Steps and conditions are only touched when sent, so changing a summary never clears the procedure.
  def create
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_CREATE)

    @runbook = upsert(nil)
    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_UPDATE)

    @runbook = upsert(@runbook)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_DELETE)

    blocked_reason = @runbook.deletion_blocked_reason
    return render json: error_response("validation_error", blocked_reason), status: :unprocessable_entity if blocked_reason

    @runbook.destroy!
    head :no_content
  end

  private

  # The API publishes no workflow, so a draft waits on its page and a member who may not publish asks the admins.
  def upsert(target)
    given = runbook_params
    upsert = Runbook::Upsert.new(current_workspace)
    return upsert.call(target, given, by: member_principal) unless upsert.runnable?(given)

    runbook = AbilityGateway.authorize!(principal: Current.principal, action_key: Workflow::CREATE_KEY, workspace: current_workspace,
                                        params: request_binding_params, context: { source: AbilityGateway::SOURCE_API }) do
      upsert.call(target, given, by: member_principal)
    end
    @workflow_said = draft_words(upsert.workflow_written)
    runbook
  rescue AbilityGateway::Denied
    raise ApiAuthentication::ForbiddenError, "API key lacks 'create' permission on 'workflows', which writing what a runbook runs needs"
  rescue Runbook::LinkedWorkflow::Refused => refused
    raise ActionController::BadRequest, refused.message
  end

  def draft_words(workflow)
    draft = workflow&.draft
    return unless draft

    service = WorkflowPublishService.new(workflow)
    unpublishable = service.unpublishable_words(draft)
    return unpublishable if unpublishable
    return "#{workflow.name} waits as a draft. Publish it from its page." if service.may_publish?(draft, by: Current.principal)

    service.ask_or_leave!(draft, by: Current.principal).words
  end

  def member_principal = (Current.principal if Current.principal.is_a?(WorkspaceMembership))

  def runbook_params
    permitted = params.permit(
      :name, :summary, :content, :external_url,
      steps: [ :title, :instruction, :tool, :undo ],
      conditions: [ :condition_field, :operator, :custom_field, values: [] ],
      inputs: [ :key, :question, :default ],
      aliases: []
    ).to_h.deep_symbolize_keys
    with_free_form(permitted)
  end

  # A step's arguments and the watch are objects of any shape, which the model checks.
  def with_free_form(permitted)
    permitted[:watch] = object_param(params[:watch]) if params.key?(:watch)
    return permitted unless permitted[:steps] && params[:steps].is_a?(Array)

    permitted[:steps] = permitted[:steps].each_with_index.map do |step, index|
      arguments = object_param(params[:steps][index].try(:[], :arguments))
      arguments ? step.merge(arguments: arguments) : step
    end
    permitted
  end

  def set_runbook
    scope = current_workspace.runbooks.active.includes(:runbook_steps)
    @runbook = if params[:id].to_s.match?(UUID_FORMAT)
      scope.find(params[:id])
    else
      scope.find_by!(slug: params[:id])
    end
  end
end
