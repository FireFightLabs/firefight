# Where a provider that sends every connection's changes to one address for its app, such as an app installed on many
# accounts, tells Firefight something changed. A delivery counts only when signed with the app's own secret, and its
# events reach each connection made through the installation it names, as does what it says of the installation itself.
# Like MapEventsController, it only queues re-reads and never names a provider. The address carries the provider's key, and its definition answers the rest.
class Api::V1::AppEventsController < ActionController::API
  MAX_BYTES = 1.megabyte

  rate_limit to: 3000, within: 1.minute, by: -> { params[:provider].to_s }, with: -> { head :too_many_requests }

  def create
    provider_key = params[:provider].to_s
    source = Integrations::MapEvents.source_of(provider_key) if IntegrationProvider.find(provider_key)
    secret = Integrations::MapEvents.app_secret(provider_key)
    return head :not_found unless source&.app_wide? && secret

    raw_body = request.raw_post
    return head :content_too_large if raw_body.bytesize > MAX_BYTES

    unless source.verify(raw_body: raw_body, headers: request.headers, secret: secret)
      Rails.logger.warn({ event: "app_events.signature_refused", provider: provider_key }.to_json)
      return head :unauthorized
    end

    payload = JSON.parse(raw_body)
    Integrations::Installations.delivered!(provider_key, source, payload, headers: request.headers)
    rows = Integrations::MapEvents.rows_for_installation(provider_key, source.installation_of(payload, headers: request.headers)).to_a
    events = rows.any? ? source.events(payload, headers: request.headers) : []
    rows.each { |row| Integrations::MapEvents.receive!(row, events) }
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
