class Api::V1::IncidentsController < Api::V1::ApiController
  before_action :set_incident, only: [ :show, :update ]

  def index
    authorize!(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_READ)

    scope = current_workspace.incidents
      .includes(:incident_status, :incident_severity, :incident_type, :declared_by)
      .recent

    scope = apply_filters(scope)

    @incidents, @pagination = paginate(scope)
  end

  def show
    authorize!(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_READ)
  end

  def create
    authorize!(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_CREATE)

    idempotency_key = params.require(:idempotency_key)

    existing = IdempotencyKey.find_by(workspace: current_workspace, key: idempotency_key, resource_type: "Incident")
    if existing
      @incident = current_workspace.incidents.find(existing.resource_id)
      render :show, status: :ok
      return
    end

    severity = current_workspace.incident_severities.active.find(params.require(:severity_id))
    status = if params[:status_id].present?
      current_workspace.incident_statuses.active.find(params[:status_id])
    else
      current_workspace.incident_statuses.default_status
    end

    incident_type = if params[:incident_type_id].present?
      current_workspace.incident_types.active.find(params[:incident_type_id])
    end

    declared_by = if params[:declared_by_id].present?
      current_workspace.workspace_memberships.find(params[:declared_by_id])
    else
      Current.api_key.created_by
    end

    visibility = params.fetch(:visibility, Incident::VISIBILITY_PUBLIC)

    @incident = Incident.create!(
      workspace: current_workspace,
      declared_by: declared_by,
      incident_status: status,
      incident_severity: severity,
      incident_type: incident_type,
      name: params.require(:name),
      summary: params[:summary],
      is_private: visibility == Incident::VISIBILITY_PRIVATE
    )

    IdempotencyKey.create!(
      workspace: current_workspace,
      key: idempotency_key,
      resource_type: "Incident",
      resource_id: @incident.id
    )

    IncidentCreationWorkflow.start!(@incident)

    render :show, status: :created
  end

  def update
    authorize!(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE)

    event_type = determine_event_type
    @incident.record_change!(event_type, changed_by: Current.api_key.created_by) do
      @incident.assign_attributes(update_params)
      resolve_associations
      @incident.save!
    end

    render :show, status: :ok
  end

  private

  def set_incident
    @incident = current_workspace.incidents
      .includes(:incident_status, :incident_severity, :incident_type, :declared_by)
      .find(params[:id])
  end

  def apply_filters(scope)
    scope = scope.where(incident_severity_id: params[:severity_id]) if params[:severity_id].present?
    scope = scope.where(incident_status_id: params[:status_id]) if params[:status_id].present?

    if params[:lifecycle_stage].present?
      scope = scope.joins(incident_status: :incident_lifecycle_stage)
        .where(incident_lifecycle_stages: { key: params[:lifecycle_stage] })
    end

    scope
  end

  def update_params
    params.permit(:name, :summary)
  end

  def resolve_associations
    if params[:severity_id].present?
      @incident.incident_severity = current_workspace.incident_severities.active.find(params[:severity_id])
    end

    if params[:status_id].present?
      @incident.incident_status = current_workspace.incident_statuses.active.find(params[:status_id])
    end

    if params[:incident_type_id].present?
      @incident.incident_type = current_workspace.incident_types.active.find(params[:incident_type_id])
    end

    if params.key?(:lead_id)
      @incident.lead = params[:lead_id].present? ? current_workspace.workspace_memberships.find(params[:lead_id]) : nil
    end
  end

  def determine_event_type
    if params[:status_id].present?
      new_status = current_workspace.incident_statuses.active.find(params[:status_id])
      if new_status.incident_lifecycle_stage.closed? || new_status.incident_lifecycle_stage.canceled?
        IncidentEvent::INCIDENT_RESOLVED
      elsif @incident.closed? && new_status.incident_lifecycle_stage.open?
        IncidentEvent::INCIDENT_REOPENED
      else
        IncidentEvent::INCIDENT_UPDATED
      end
    elsif params.key?(:lead_id)
      IncidentEvent::LEAD_ASSIGNED
    else
      IncidentEvent::INCIDENT_UPDATED
    end
  end
end
