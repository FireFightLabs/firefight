# A dashboard request parked behind an approval is replayed through the
# router once someone approves, as the requester, carrying the approval so
# the gateway admits it. The person cannot retry a click they made an hour
# ago, so Firefight retries it for them.
class WebRequestReplay
  ENV_KEY = "firefight.web_replay".freeze

  Result = Struct.new(:success?, :message, keyword_init: true)

  # The body is kept byte for byte, in its original encoding, so the replay
  # parses to the same parameters and carries the same digest.
  def self.payload_for(request, membership)
    {
      path: request.path,
      method: request.request_method,
      body: request.raw_post,
      content_type: request.media_type,
      membership_id: membership.id
    }
  end

  def self.call(approval, payload)
    env = Rack::MockRequest.env_for(
      payload["path"],
      method: payload["method"],
      input: payload["body"].to_s,
      "CONTENT_TYPE" => payload["content_type"].to_s
    )
    env[ENV_KEY] = { "membership_id" => payload["membership_id"], "approval_id" => approval.id }

    status, = Rails.application.routes.call(env)
    flash = env["action_dispatch.request.flash_hash"]
    notice = flash && flash[:notice]
    alert = flash && flash[:alert]

    Result.new(success?: status < 400 && alert.nil? && notice.present?, message: alert || notice)
  end
end
