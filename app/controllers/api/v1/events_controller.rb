class Api::V1::EventsController < Api::V1::BaseController
  def create
    payload = parse_payload

    if payload["type"] == "url_verification"
      render json: { challenge: payload["challenge"] }
      return
    end

    # The Slack verification token must not reach job arguments because job arguments are logged.
    ProcessEventJob.perform_later(Platforms::SLACK, payload.except("token"))
    head :ok
  end

  private

  def parse_payload
    JSON.parse(request.raw_post)
  rescue JSON::ParserError
    {}
  end
end
