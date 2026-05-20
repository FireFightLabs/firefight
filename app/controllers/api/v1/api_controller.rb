class Api::V1::ApiController < ActionController::API
  include ApiAuthentication

  rate_limit to: 1000, within: 1.minute, by: -> { Current.api_key&.id }, with: :rate_limit_exceeded

  before_action :annotate_trace_source

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :validation_error
  rescue_from ActionController::ParameterMissing, with: :bad_request
  rescue_from ApiAuthentication::ForbiddenError, with: :forbidden

  private

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

  def bad_request(exception)
    render json: error_response("bad_request", exception.message), status: :bad_request
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
