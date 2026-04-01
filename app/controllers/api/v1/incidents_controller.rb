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
    severity = current_workspace.incident_severities.active.find(params.require(:severity_id))
    status = params[:status_id].present? ? current_workspace.incident_statuses.active.find(params[:status_id]) : current_workspace.incident_statuses.default_status
    incident_type = current_workspace.incident_types.active.find(params[:incident_type_id]) if params[:incident_type_id].present?
    declared_by = current_workspace.workspace_memberships.find(params[:declared_by_id]) if params[:declared_by_id].present?

    custom_fields = validate_custom_fields(params[:custom_fields])

    ActiveRecord::Base.transaction do
      @incident = lifecycle_service.create(
        declared_by: declared_by,
        incident_status: status,
        incident_severity: severity,
        incident_type: incident_type,
        name: params.require(:name),
        summary: params[:summary],
        custom_fields: custom_fields,
        is_private: params.fetch(:visibility, Incident::VISIBILITY_PUBLIC) == Incident::VISIBILITY_PRIVATE,
        source: params.fetch(:source, Current.api_key.name),
        source_api_key: Current.api_key
      )

      IdempotencyKey.create!(
        workspace: current_workspace,
        key: idempotency_key,
        resource_type: "Incident",
        resource_id: @incident.id
      )
    end

    render :show, status: :created
  rescue ActiveRecord::RecordNotUnique
    existing = IdempotencyKey.find_by!(workspace: current_workspace, key: idempotency_key, resource_type: "Incident")
    @incident = current_workspace.incidents.find(existing.resource_id)
    render :show, status: :ok
  end

  def update
    authorize!(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE)

    resolve_and_apply_update

    @incident.reload
    render :show, status: :ok
  end

  private

  def set_incident
    @incident = current_workspace.incidents
      .includes(:incident_status, :incident_severity, :incident_type, :declared_by)
      .find(params[:id])
  end

  def lifecycle_service
    @lifecycle_service ||= IncidentLifecycleService.new(current_workspace)
  end

  def resolve_and_apply_update
    new_status = current_workspace.incident_statuses.active.find(params[:status_id]) if params[:status_id].present?
    new_severity = current_workspace.incident_severities.active.find(params[:severity_id]) if params[:severity_id].present?
    new_type = current_workspace.incident_types.active.find(params[:incident_type_id]) if params[:incident_type_id].present?
    new_lead = current_workspace.workspace_memberships.find(params[:lead_id]) if params[:lead_id].present?
    changed_by = Current.api_key.created_by

    if new_status && (new_status.incident_lifecycle_stage.closed? || new_status.incident_lifecycle_stage.canceled?)
      attrs = { incident_status: new_status }
      attrs[:incident_severity] = new_severity if new_severity
      attrs[:name] = params[:name] if params.key?(:name)
      attrs[:summary] = params[:summary] if params.key?(:summary)
      lifecycle_service.close(@incident, attrs, changed_by: changed_by)
    elsif new_status && @incident.closed? && new_status.incident_lifecycle_stage.open?
      lifecycle_service.reopen(@incident, { incident_status: new_status }, changed_by: changed_by)
    elsif params.key?(:lead_id)
      lifecycle_service.assign_lead(@incident, new_lead, changed_by: changed_by)
    else
      attrs = {}
      attrs[:name] = params[:name] if params.key?(:name)
      attrs[:summary] = params[:summary] if params.key?(:summary)
      attrs[:incident_status] = new_status if new_status
      attrs[:incident_severity] = new_severity if new_severity
      attrs[:incident_type] = new_type if new_type
      lifecycle_service.update(@incident, attrs, changed_by: changed_by)
    end
  end

  def validate_custom_fields(raw_custom_fields)
    return {} if raw_custom_fields.blank?

    fields = raw_custom_fields.respond_to?(:to_unsafe_h) ? raw_custom_fields.to_unsafe_h : raw_custom_fields.to_h
    resolver = IncidentFormResolver.new(current_workspace)

    begin
      result = resolver.validate_submission(IncidentForm::SLUG_DECLARE, fields)
      result[:custom_fields]
    rescue ActiveRecord::RecordNotFound
      fields
    end
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
end
