# Alert ingest endpoint. Authenticated per-source (endpoint_path + secret via
# the provider adapter), not via Slack signatures or public-API Bearer keys —
# so it inherits neither BaseController nor ApiController.
class Api::V1::AlertsController < ActionController::API
  def create
    source = AlertSource.enabled.find_by(endpoint_path: params[:endpoint_path])
    return head :not_found unless source
    return head :too_many_requests unless within_rate_limit?(source)

    raw_body = request.raw_post
    unless source.adapter.verify(headers: request.headers, raw_body: raw_body, source: source)
      return head :unauthorized
    end

    payload = JSON.parse(raw_body)
    normalized = source.adapter.normalize(payload, source: source)
    if normalized.empty?
      return render json: { ok: false, error: "unrecognized payload for provider #{source.provider}" }, status: :unprocessable_entity
    end

    service = AlertIngestService.new(source)
    normalized.each { |fields| service.ingest(fields, payload) }

    render json: { ok: true, received: normalized.size }
  rescue JSON::ParserError
    render json: { ok: false, error: "invalid JSON" }, status: :bad_request
  end

  private

  # A runaway source gets 429s (providers retry) instead of saturating web
  # workers and the database for everyone.
  def within_rate_limit?(source)
    key = "alerts:rate:#{source.id}:#{Time.current.to_i / 60}"
    count = Rails.cache.increment(key, 1, expires_in: 2.minutes)
    count.nil? || count <= source.rate_limit_per_minute
  end
end
