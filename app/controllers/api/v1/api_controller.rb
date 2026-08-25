class Api::V1::ApiController < ActionController::API
  include ApiAuthentication

  rate_limit to: 1000, within: 1.minute, by: -> { Current.api_key&.id }, with: :rate_limit_exceeded

  before_action :block_suspended_workspace
  before_action :annotate_trace_source

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :validation_error
  rescue_from Incident::NotActive, with: :incident_not_active
  rescue_from IncidentLifecycleService::RoleNotUnassignable, with: :incident_not_active
  rescue_from IncidentFormResolver::ValidationError, with: :form_validation_error
  rescue_from ActionController::ParameterMissing, with: :bad_request
  rescue_from ApiAuthentication::ForbiddenError, with: :forbidden
  rescue_from AbilityGateway::PendingApproval, with: :pending_approval
  rescue_from Ability::Approval::NotAllowed, with: :approval_not_allowed

  private

  def block_suspended_workspace
    return unless Current.workspace&.suspended?

    render json: error_response("workspace_suspended", Current.workspace.suspension_message), status: :forbidden
  end

  def annotate_trace_source
    OpenTelemetry::Trace.current_span.add_attributes({
      "firefight.source" => "api",
      "firefight.api_key.name" => Current.api_key&.name,
      "firefight.workspace.id" => Current.workspace&.id,
      "firefight.api.client_source" => params[:source]
    }.compact)
  end

  def rate_limit_exceeded
    render json: error_response("rate_limit_exceeded", "Rate limit exceeded. Try again later."), status: :too_many_requests
  end

  def not_found(_exception)
    render json: error_response("not_found", "Resource not found"), status: :not_found
  end

  def validation_error(exception)
    errors = exception.record.errors.map { |e| { field: e.attribute.to_s, message: e.message } }
    render json: error_response("validation_error", exception.message, errors: errors), status: :unprocessable_entity
  end

  def form_validation_error(exception)
    errors = exception.field_errors.map { |message| { message: message } }
    render json: error_response("validation_error", exception.message, errors: errors), status: :unprocessable_entity
  end

  def incident_not_active(exception)
    render json: error_response("incident_not_active", exception.message), status: :unprocessable_entity
  end

  def approval_not_allowed(exception)
    render json: error_response("approval_not_allowed", exception.message), status: :unprocessable_entity
  end

  def environment_ids_for(slugs)
    PolicyRule::ApprovalRuleChanges.environment_ids(current_workspace, slugs)
  end

  def bad_request(exception)
    render json: error_response("bad_request", exception.message), status: :bad_request
  end

  def pending_approval(exception)
    approval = exception.approval
    body = error_response(
      "approval_required",
      "This action requires approval by a workspace #{approval.required_role}. " \
      "Retry the identical request with the 'X-Approval-Id: #{approval.id}' header once approved."
    )
    render json: body.merge(approval_id: approval.id, approval_status: approval.status), status: :accepted
  end

  def forbidden(exception)
    render json: error_response("forbidden", exception.message), status: :forbidden
  end

  def error_response(type, message, errors: nil)
    response = { error: { type: type, message: message, request_id: request.request_id } }
    response[:error][:errors] = errors if errors
    response
  end

  def paginate(scope)
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    per_page = [ [ params.fetch(:per_page, 25).to_i, 1 ].max, 100 ].min
    total = scope.count
    records = scope.offset((page - 1) * per_page).limit(per_page)
    [ records, { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil } ]
  end
end
