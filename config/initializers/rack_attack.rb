# /api/v1/* endpoints are protected by Slack signature verification — not rate limited by IP
# since Slack sends webhooks from a rotating pool of IPs across their infrastructure.

# Throttle the OAuth entry point to prevent abuse of the Slack OAuth flow.
Rack::Attack.throttle("auth by ip", limit: 20, period: 60.seconds) do |req|
  req.ip if req.path.start_with?("/auth/")
end

Rack::Attack.throttled_responder = lambda do |_request|
  [ 429, { "Content-Type" => "application/json" }, [ { error: "Too many requests" }.to_json ] ]
end
