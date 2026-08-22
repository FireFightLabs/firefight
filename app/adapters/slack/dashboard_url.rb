module Slack
  module DashboardUrl
    def self.incident(incident)
      build(:incident_url, id: incident.id)
    end

    def self.postmortem(incident)
      build(:incident_postmortem_url, incident_id: incident.id)
    end

    def self.build(helper, params)
      host = ENV["APP_HOST"].presence
      return nil unless host

      Rails.application.routes.url_helpers.public_send(
        helper,
        **params,
        host: host,
        protocol: ENV.fetch("APP_PROTOCOL", "https")
      )
    rescue StandardError => e
      Rails.logger.warn({ event: "slack.dashboard_url.build_failed", helper: helper, error: e.message }.to_json)
      nil
    end
    private_class_method :build
  end
end
