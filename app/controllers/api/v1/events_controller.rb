class Api::V1::EventsController < Api::V1::BaseController
  def create
    payload = parse_payload

    if payload["type"] == "url_verification"
      render json: { challenge: payload["challenge"] }
      return
    end

    ProcessEventJob.perform_later(Platforms::SLACK, payload)
    head :ok
  end

  private

  def parse_payload
    JSON.parse(request.raw_post)
  rescue JSON::ParserError
    {}
  end
end
