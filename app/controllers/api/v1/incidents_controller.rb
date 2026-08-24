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
    return render_replay(idempotency_key) if replayed?(idempotency_key)

    severity = current_workspace.incident_severities.active.find(params.require(:severity_id))
    status = params[:status_id].present? ? current_workspace.incident_statuses.active.find(params[:status_id]) : current_workspace.incident_statuses.default_status
    incident_type = current_workspace.incident_types.active.find(params[:incident_type_id]) if params[:incident_type_id].present?
    declared_by = current_workspace.workspace_memberships.find(params[:declared_by_id]) if params[:declared_by_id].present?

    custom_fields = validate_custom_fields(params[:custom_fields])

    lost_key_race = false
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

      begin
        IdempotencyKey.create!(
          workspace: current_workspace,
          key: idempotency_key,
          resource_type: IdempotencyKey::RESOURCE_INCIDENT,
          resource_id: @incident.id
        )
      rescue ActiveRecord::RecordNotUnique
        # A concurrent request with the same key committed first. Only this
        # insert is rescued so any other unique violation still surfaces as
        # the error it is instead of a replay.
        lost_key_race = true
        raise ActiveRecord::Rollback
      end
    end

    return render_replay(idempotency_key) if lost_key_race

    render :show, status: :created
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

  # Every field in the body lands in one request. The lifecycle service
  # decides from the status what kind of change this is (update, close,
  # cancel, reopen, accept) and the other fields ride along with it.
  def resolve_and_apply_update
    attrs = {}
    attrs[:name] = params[:name] if params.key?(:name)
    attrs[:summary] = params[:summary] if params.key?(:summary)
    attrs[:incident_status] = current_workspace.incident_statuses.active.find(params[:status_id]) if params[:status_id].present?
    attrs[:incident_severity] = current_workspace.incident_severities.active.find(params[:severity_id]) if params[:severity_id].present?
    attrs[:incident_type] = current_workspace.incident_types.active.find(params[:incident_type_id]) if params[:incident_type_id].present?
    changed_by = Current.api_key

    if params.key?(:lead_id)
      lead = params[:lead_id].present? ? current_workspace.workspace_memberships.find(params[:lead_id]) : nil
      # A lead on its own keeps the dedicated lead event and announcement. Next
      # to other fields it rides inside that change. Clearing the lead goes
      # through the role rules, which refuse it with the reason.
      return lifecycle_service.assign_role(@incident, lead_role, lead, changed_by: changed_by) if attrs.empty? || lead.nil?

      attrs[:lead] = lead
    end

    lifecycle_service.change_status(@incident, attrs, changed_by: changed_by)
  end

  def lead_role
    current_workspace.ensure_incident_role!(IncidentRole::SLUG_INCIDENT_LEAD)
  end

  def replayed?(idempotency_key)
    IdempotencyKey.exists?(workspace: current_workspace, key: idempotency_key, resource_type: IdempotencyKey::RESOURCE_INCIDENT)
  end

  def render_replay(idempotency_key)
    existing = IdempotencyKey.find_by!(workspace: current_workspace, key: idempotency_key, resource_type: IdempotencyKey::RESOURCE_INCIDENT)
    @incident = current_workspace.incidents.find(existing.resource_id)
    render :show, status: :ok
  end

  def validate_custom_fields(raw_custom_fields)
    return {} if raw_custom_fields.blank?

    fields = raw_custom_fields.respond_to?(:to_unsafe_h) ? raw_custom_fields.to_unsafe_h : raw_custom_fields.to_h
    IncidentFormResolver.new(current_workspace).validate_custom_fields!(IncidentForm::SLUG_DECLARE, fields)
  end

  def apply_filters(scope)
    scope = scope.where(incident_severity_id: params[:severity_id]) if params[:severity_id].present?
    scope = scope.where(incident_status_id: params[:status_id]) if params[:status_id].present?

    scope = scope.by_lifecycle_stage_keys(params[:lifecycle_stage]) if params[:lifecycle_stage].present?

    scope
  end
end
