# Where a provider tells Firefight something on the map changed. The address is one connection's own, and a delivery
# counts only when the provider signed it as it documents (its definition's map_events, a MapEventSource), checked
# against the secret kept for that connection. The events only queue a re-read, so a delivery never writes the map
# itself. So it inherits neither BaseController nor ApiController.
class Api::V1::MapEventsController < ActionController::API
  MAX_BYTES = 1.megabyte

  rate_limit to: 600, within: 1.minute, by: -> { params[:token].to_s }, with: -> { head :too_many_requests }

  def create
    row = IntegrationEnvironment.reachable.find_by(map_events_token: params[:token].to_s) if params[:token].present?
    source = row && Integrations::MapEvents.source_of(row.integration.provider)
    return head :not_found unless source

    raw_body = request.raw_post
    return head :content_too_large if raw_body.bytesize > MAX_BYTES

    # Nothing is accepted before a secret is saved, unless Firefight registered the webhook and the provider signs it its own way.
    secrets = row.map_events_secrets.presence || ([ nil ] if row.map_events_webhook_id.present?)
    unless secrets&.any? { |secret| source.verify(raw_body: raw_body, headers: request.headers, secret: secret) }
      Rails.logger.warn({ event: "map_events.signature_refused", integration_environment_id: row.id, provider: row.integration.provider }.to_json)
      return head :unauthorized
    end

    payload = JSON.parse(raw_body)
    Integrations::MapEvents.delivered!(row, source, payload)
    Integrations::MapEvents.receive!(row, source.events(payload, headers: request.headers))
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
