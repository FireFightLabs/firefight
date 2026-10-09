# Where an issue tracker's webhook tells Firefight an issue changed. The address is the workspace's own, and a delivery
# counts only when the tracker signed it with the secret kept on the tracker connection's row, checked as the tracker
# documents (Integrations::Issues.verify). So it inherits neither BaseController nor ApiController.
class Api::V1::IssueEventsController < ActionController::API
  MAX_BYTES = 1.megabyte

  rate_limit to: 600, within: 1.minute, by: -> { params[:token].to_s }, with: -> { head :too_many_requests }

  def create
    workspace = Workspace.find_by(issue_webhook_token: params[:token].to_s) if params[:token].present?
    integration = workspace&.issue_sync_connection
    row = workspace&.issue_webhook_row(integration)
    return head :not_found unless row

    raw_body = request.raw_post
    return head :content_too_large if raw_body.bytesize > MAX_BYTES

    unless Integrations::Issues.verify(integration.provider, raw_body: raw_body, headers: request.headers, secret: row.issue_webhook_secret,
                                                            webhook_id: row.issue_webhook_id)
      Rails.logger.warn({ event: "issue_events.signature_refused", workspace_id: workspace.id, provider: integration.provider }.to_json)
      return head :unauthorized
    end

    event = Integrations::Issues.event(integration.provider, JSON.parse(raw_body))
    IssueSyncService.new(workspace).receive(event) if event
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
