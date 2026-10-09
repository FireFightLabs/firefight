# Every write goes through IncidentActionService, so an item raised over the API
# matches one raised from Slack.
class Api::V1::ActionItemsController < Api::V1::ApiController
  before_action :set_incident
  before_action :set_action_item, only: [ :update ]

  def index
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)

    @action_items, @pagination = paginate(@incident.incident_actions.active.order(:created_at))
  end

  def create
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    @action_item = service.create_action(
      incident: @incident,
      created_by: Current.principal,
      action_type: params.fetch(:kind, IncidentAction::ACTION_TYPE_ACTION),
      description: params.require(:description),
      assignee: current_workspace.workspace_memberships.resolve!(params[:assignee_id])
    )

    render :show, status: :created
  end

  # One call covers renaming, taking, handing over, finishing, reopening and letting go. The service decides which
  # event is recorded. Every refusal is checked first, so a refused request changes nothing.
  def update
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    refusal = @action_item.change_blocked_reason(description: params.key?(:description) ? params[:description].to_s : nil, status: params[:status])
    return render json: error_response("validation_error", refusal), status: :unprocessable_entity if refusal

    if params.key?(:description)
      refusal = service.rename_action(action: @action_item, description: params[:description], renamed_by: Current.principal)
      return render json: error_response("validation_error", refusal), status: :unprocessable_entity if refusal
    end

    if params[:status] == IncidentAction::STATUS_OPEN
      refusal = service.open_action(action: @action_item.reload, opened_by: Current.principal)
      return render json: error_response("validation_error", refusal), status: :unprocessable_entity if refusal
    end

    assign_item if params.key?(:assignee_id)
    service.complete_action(action: @action_item.reload, completed_by: Current.principal) if params[:status] == IncidentAction::STATUS_DONE

    @action_item.reload
    render :show
  end

  private

  def assign_item
    service.assign_action(
      action: @action_item,
      assignee: current_workspace.workspace_memberships.resolve!(params[:assignee_id]) || Current.principal,
      assigned_by: Current.principal
    )
  end

  def service
    @service ||= IncidentActionService.new(current_workspace)
  end

  def set_incident
    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
  end

  def set_action_item
    @action_item = @incident.incident_actions.active.find(params[:id])
  end
end
