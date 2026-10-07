# /api/v1 is not throttled by IP. Slack signs those requests and sends them from a rotating IP pool.
Rack::Attack.throttle("auth by ip", limit: 20, period: 60.seconds) do |req|
  req.ip if req.path.start_with?("/auth/")
end

# Not a brute-force defence, the digest space is too large. It limits a race to redeem a leaked code.
Rack::Attack.throttle("invite_code_claim by ip", limit: 10, period: 60.seconds) do |req|
  req.ip if req.path == "/invite-code/claim" && req.post?
end

# Asking for a sign-in link sends an email, so both the sender and the inbox are capped.
Rack::Attack.throttle("email sign-in link by ip", limit: 5, period: 1.minute) do |req|
  req.ip if req.path == "/auth/email" && req.post?
end

Rack::Attack.throttle("email sign-in link by email", limit: 5, period: 1.hour) do |req|
  RackAttackParams.email(req) if req.path == "/auth/email" && req.post?
end

Rack::Attack.throttle("email sign-in confirm by ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.path == "/auth/email/confirm" && req.post?
end

Rack::Attack.throttle("invitation accept by ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.path == "/auth/invitation" && req.post?
end

# Each new workspace is seeded with its defaults, so one address creates a handful an hour at most.
Rack::Attack.throttle("workspace signup by ip", limit: 5, period: 1.hour) do |req|
  req.ip if req.path == "/signup/workspace" && req.post?
end

# Every invitation sends an email. WorkspaceInvitation also caps each workspace, whoever sends.
Rack::Attack.throttle("workspace invitations by ip", limit: 30, period: 1.hour) do |req|
  req.ip if req.post? && req.path.start_with?("/app/settings/members/invitations")
end

Rack::Attack.throttled_responder = lambda do |request|
  if request.path.start_with?("/api/")
    [ 429, { "Content-Type" => "application/json" }, [ { error: "Too many requests" }.to_json ] ]
  else
    period = request.env.dig("rack.attack.match_data", :period).to_i
    wait = period >= 1.hour ? "an hour" : "a minute"
    body = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Too many requests</title></head><body><h1>Too many requests</h1><p>Please try again in #{wait}.</p></body></html>"
    [ 429, { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => [ period, 60 ].max.to_s }, [ body ] ]
  end
end
