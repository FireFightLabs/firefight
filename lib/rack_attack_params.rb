# Rack::Attack runs before Rails parses the body, and the dashboard posts JSON, so a throttle keyed on a field reads
# the body itself and rewinds it for the app.
module RackAttackParams
  def self.email(request)
    value = json?(request) ? json_body(request)["email"] : request.params["email"]
    value.to_s.strip.downcase.presence
  end

  def self.json?(request) = request.media_type == "application/json"

  def self.json_body(request)
    body = request.body.read
    request.body.rewind
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
  private_class_method :json?, :json_body
end
