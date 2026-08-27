# /api/v1/* endpoints are protected by Slack signature verification, not rate limited by IP
# since Slack sends webhooks from a rotating pool of IPs across their infrastructure.

# Throttle the OAuth entry point to prevent abuse of the Slack OAuth flow.
Rack::Attack.throttle("auth by ip", limit: 20, period: 60.seconds) do |req|
  req.ip if req.path.start_with?("/auth/")
end

# Throttle invite code claim attempts. Not a brute-force defense (digest space is
# infeasible). It protects against race-to-redeem if a code is leaked publicly.
Rack::Attack.throttle("invite_code_claim by ip", limit: 10, period: 60.seconds) do |req|
  req.ip if req.path == "/invite-code/claim" && req.post?
end

Rack::Attack.throttled_responder = lambda do |request|
  if request.path.start_with?("/api/")
    [ 429, { "Content-Type" => "application/json" }, [ { error: "Too many requests" }.to_json ] ]
  else
    body = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Too many requests</title></head><body><h1>Too many requests</h1><p>Please try again in a minute.</p></body></html>"
    [ 429, { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => "60" }, [ body ] ]
  end
end
