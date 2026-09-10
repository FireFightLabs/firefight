module SlackSignatureHelper
  def generate_slack_signature(body:, timestamp: Time.now.to_i, signing_secret: SlackConstants::SIGNING_SECRET)
    sig_basestring = "#{SlackConstants::SIGNATURE_VERSION}:#{timestamp}:#{body}"
    signature = "#{SlackConstants::SIGNATURE_VERSION}=" +
                OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)

    {
      "X-Slack-Request-Timestamp" => timestamp.to_s,
      "X-Slack-Signature" => signature
    }
  end

  def slack_command_request(params = {})
    default_params = {
      token: "test-token",
      team_id: "T12345678",
      team_domain: "test-workspace",
      channel_id: "C12345678",
      channel_name: "general",
      user_id: "U12345678",
      user_name: "alice",
      command: "/firefight",
      text: "",
      response_url: "https://hooks.slack.com/commands/T12345678/12345/abc123",
      trigger_id: "123456.789.abc123",
      api_app_id: "A12345678"
    }

    params = default_params.merge(params)
    body = params.to_query
    headers = generate_slack_signature(body: body)

    { body: body, headers: headers }
  end

  def slack_interaction_request(payload = {})
    default_payload = {
      type: "view_submission",
      team: {
        id: "T12345678",
        domain: "test-workspace"
      },
      user: {
        id: "U12345678",
        username: "alice",
        name: "Alice Smith"
      },
      view: {
        callback_id: Identifiers::INCIDENT_CREATION_MODAL,
        type: "modal",
        private_metadata: "",
        state: {
          values: {}
        }
      }
    }

    payload = default_payload.deep_merge(payload)
    payload_json = payload.to_json
    body = "payload=#{CGI.escape(payload_json)}"
    headers = generate_slack_signature(body: body)

    { body: body, headers: headers }
  end
end
