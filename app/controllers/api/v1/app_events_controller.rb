# Where a provider that sends every connection's changes to one address for its app, such as an app installed on many
# accounts, tells Firefight something changed. A delivery counts only when signed with the app's own secret, and its
# events reach each connection made through the installation it names, as does what it says of the installation itself.
# The same address takes an app's agent sessions (Integrations::AgentSessions), for a provider whose app people assign
# work to, and the changes to issues sent for a workspace whose chosen tracker is connected through the app
# (IssueSyncService.app_delivered!). Like MapEventsController, it only queues work and never names a provider. The
# address carries the provider's key, and its definition answers the rest.
class Api::V1::AppEventsController < ActionController::API
  MAX_BYTES = 1.megabyte

  rate_limit to: 3000, within: 1.minute, by: -> { params[:provider].to_s }, with: -> { head :too_many_requests }

  def create
    provider_key = params[:provider].to_s
    known = IntegrationProvider.find(provider_key).present?
    map_source = Integrations::MapEvents.source_of(provider_key) if known
    map_source = nil unless map_source&.app_wide?
    source = map_source || (Integrations::AgentSessions.source_of(provider_key) if known)
    secret = Integrations::MapEvents.app_secret(provider_key)
    return head :not_found unless source && secret

    raw_body = request.raw_post
    return head :content_too_large if raw_body.bytesize > MAX_BYTES

    unless source.verify(raw_body: raw_body, headers: request.headers, secret: secret)
      Rails.logger.warn({ event: "app_events.signature_refused", provider: provider_key }.to_json)
      return head :unauthorized
    end

    payload = JSON.parse(raw_body)
    Integrations::Installations.delivered!(provider_key, source, payload, headers: request.headers)
    rows = Integrations::MapEvents.rows_for_installation(provider_key, source.installation_of(payload, headers: request.headers)).to_a
    receive_map_delivery(map_source, rows, payload) if map_source
    Integrations::AgentSessions.delivered!(provider_key, rows, payload)
    IssueSyncService.app_delivered!(provider_key, rows, payload)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def receive_map_delivery(source, rows, payload)
    events = rows.any? ? source.events(payload, headers: request.headers) : []
    Integrations::MapEvents.receive_delivery!(rows, events, payload, headers: request.headers)
    Integrations::MapEvents.nudge_pull_requests!(rows, payload, headers: request.headers)
    Integrations::MapEvents.report_security_events!(rows, payload, headers: request.headers)
    Integrations::MapEvents.nudge_handbook!(rows, payload, headers: request.headers)
  end
end
