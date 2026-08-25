# Alert ingest endpoint. Authenticated per-source (endpoint_path + secret via
# the provider adapter), not via Slack signatures or public-API Bearer keys.
# So it inherits neither BaseController nor ApiController.
class Api::V1::AlertsController < ActionController::API
  def create
    source = AlertSource.enabled.find_by(endpoint_path: params[:endpoint_path])
    return head :not_found unless source

    if source.workspace.suspended?
      return reject(source, "workspace suspended", :forbidden,
                    error: source.workspace.suspension_message)
    end

    raw_body = request.raw_post
    if source.payload_too_large?(raw_body.bytesize)
      return reject(source, "payload too large", :content_too_large)
    end

    adapter = AlertProviders.for(source.provider)
    unless adapter.verify(headers: request.headers, raw_body: raw_body, source: source)
      return reject(source, "invalid token", :unauthorized)
    end

    payload = JSON.parse(raw_body)
    items = adapter.normalize(payload, source: source)
    if items.empty?
      return reject(source, "unrecognized payload", :unprocessable_entity,
                    error: "unrecognized payload for provider #{source.provider}")
    end
    if source.batch_too_large?(items.size)
      return reject(source, "batch too large", :unprocessable_entity,
                    error: "batch exceeds #{AlertSource::StormControl::MAX_BATCH_ITEMS} items")
    end
    return reject(source, "rate limited", :too_many_requests) unless source.admit?(items.size)

    source.record_received!

    service = AlertIngestService.new(source)
    failed = 0
    items.each do |item|
      service.ingest(item[:fields], item[:payload])
    rescue StandardError => e
      failed += 1
      Rails.logger.error({ event: "alert_ingest.item_failed", alert_source_id: source.id, error: e.message }.to_json)
    end

    render json: { ok: failed.zero?, received: items.size - failed, failed: failed }
  rescue JSON::ParserError
    reject(source, "invalid JSON", :bad_request, error: "invalid JSON")
  end

  private

  def reject(source, reason, status, error: nil)
    source.record_rejection!(reason)
    if error
      render json: { ok: false, error: error }, status: status
    else
      head status
    end
  end
end
