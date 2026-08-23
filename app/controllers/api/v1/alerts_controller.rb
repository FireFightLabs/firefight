# Alert ingest endpoint. Authenticated per-source (endpoint_path + secret via
# the provider adapter), not via Slack signatures or public-API Bearer keys.
# So it inherits neither BaseController nor ApiController.
class Api::V1::AlertsController < ActionController::API
  MAX_PAYLOAD_BYTES = 512.kilobytes
  MAX_BATCH_ITEMS = 100

  def create
    source = AlertSource.enabled.find_by(endpoint_path: params[:endpoint_path])
    return head :not_found unless source

    if source.workspace.suspended?
      return reject(source, "workspace suspended", :forbidden,
                    error: source.workspace.suspension_message)
    end

    raw_body = request.raw_post
    if raw_body.bytesize > MAX_PAYLOAD_BYTES
      return reject(source, "payload too large", :content_too_large)
    end

    unless source.adapter.verify(headers: request.headers, raw_body: raw_body, source: source)
      return reject(source, "invalid token", :unauthorized)
    end

    payload = JSON.parse(raw_body)
    items = source.adapter.normalize(payload, source: source)
    if items.empty?
      return reject(source, "unrecognized payload", :unprocessable_entity,
                    error: "unrecognized payload for provider #{source.provider}")
    end
    if items.size > MAX_BATCH_ITEMS
      return reject(source, "batch too large", :unprocessable_entity,
                    error: "batch exceeds #{MAX_BATCH_ITEMS} items")
    end
    unless within_rate_limit?(source, items.size)
      return reject(source, "rate limited", :too_many_requests)
    end

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

  # A runaway source gets 429s (providers retry) instead of saturating web
  # workers and the database for everyone. Counts alerts, not requests, so a
  # batch can't smuggle unbounded work past the limit.
  def within_rate_limit?(source, item_count)
    key = "alerts:rate:#{source.id}:#{Time.current.to_i / 60}"
    count = Rails.cache.increment(key, item_count, expires_in: 2.minutes)
    count.nil? || count <= source.rate_limit_per_minute
  end
end
