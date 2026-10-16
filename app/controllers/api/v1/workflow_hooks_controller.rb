# Where a workflow whose trigger is an inbound webhook is started from outside, by a POST to its own address, with a JSON
# object as the body, signed with the workflow's secret as Firefight signs its outbound webhooks (Workflow::Hook). The
# address names the workflow and the signature is the only proof of who sent it, so it inherits neither BaseController
# nor ApiController. The body is read as it came, never as parameters. A workspace without workflows, a workflow
# switched off or one that starts some other way answers not found, as an address that never existed does.
class Api::V1::WorkflowHooksController < ActionController::API
  MAX_BYTES = 100.kilobytes

  rate_limit to: 120, within: 1.minute, by: -> { request.path_parameters[:token].to_s }, with: -> { render json: { error: "Too many deliveries, try again in a minute." }, status: :too_many_requests }

  def create
    workflow = Workflow.includes(:live_version, :workspace).find_by(hook_token: request.path_parameters[:token].to_s)
    return head :not_found unless workflow && FeatureFlags.enabled?(workflow.workspace, FeatureFlags::WORKFLOWS) && workflow.hooked?

    raw_body = request.raw_post
    return render json: { error: "The body is larger than #{MAX_BYTES / 1.kilobyte} KB." }, status: :content_too_large if raw_body.bytesize > MAX_BYTES

    signed = workflow.hook_signed?(raw_body, timestamp: request.headers[Workflow::Hook::TIMESTAMP_HEADER], signature: request.headers[Workflow::Hook::SIGNATURE_HEADER])
    return render json: { error: "The signature is missing, wrong or more than five minutes old." }, status: :unauthorized unless signed

    body = JSON.parse(raw_body)
    return render json: { error: "The body must be a JSON object." }, status: :unprocessable_content unless body.is_a?(Hash)

    run = WorkflowTriggerService.new(workflow.workspace).hooked!(workflow, body: body, delivery: request.headers[Workflow::Hook::DELIVERY_HEADER])
    return render json: { started: false, reason: "What it was sent does not meet the trigger's conditions." }, status: :ok unless run

    render json: { started: true, run_id: run.id }, status: :accepted
  rescue JSON::ParserError
    render json: { error: "The body must be a JSON object." }, status: :bad_request
  rescue Workflow::Run::Refused => refused
    render json: { started: false, error: refused.message }, status: :conflict
  end
end
