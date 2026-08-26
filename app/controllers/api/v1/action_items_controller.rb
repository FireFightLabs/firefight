# The work an incident generates, as data. Creating, taking and finishing an
# item all go through IncidentActionService, so an item raised over the API is
# indistinguishable from one raised by a button in Slack.
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
      assignee: member(params[:assignee_id])
    )

    render :show, status: :created
  end

  # One call covers taking an item, handing it over and finishing it, because
  # from the caller's side each is the same sentence: this item now looks like
  # this. Which event gets recorded is the service's decision, not the body's.
  def update
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    assign_item if params.key?(:assignee_id)

    if params[:status] == IncidentAction::STATUS_DONE
      blocked_reason = @action_item.reload.completion_blocked_reason
      return render json: error_response("validation_error", blocked_reason), status: :unprocessable_entity if blocked_reason

      service.complete_action(action: @action_item, completed_by: Current.principal)
    end

    @action_item.reload
    render :show
  end

  private

  def assign_item
    service.assign_action(
      action: @action_item,
      assignee: member(params[:assignee_id]) || Current.principal,
      assigned_by: Current.principal
    )
  end

  def service
    @service ||= IncidentActionService.new(current_workspace)
  end

  def member(reference)
    return nil if reference.blank?

    current_workspace.workspace_memberships.resolve(reference) ||
      raise(ActiveRecord::RecordNotFound, "No workspace member matches #{reference.inspect}")
  end

  def set_incident
    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
  end

  def set_action_item
    @action_item = @incident.incident_actions.active.find(params[:id])
  end
end
