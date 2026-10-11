module Integrations
  module Pagers
    # Raises a PagerDuty incident on a service, which pages whoever the service's escalation policy names, and keeps it in
    # step through PagerDuty's REST API (PagerdutyApi). The hosted MCP server's manage_incidents makes the same changes,
    # so each call is authorized as that tool, and reads as the browse tool that reads the same thing.
    class Pagerduty < Pager
      MANAGE = "manage_incidents".freeze
      BROWSE_INCIDENTS = "browse_incidents".freeze
      BROWSE_SERVICES = "browse_services".freeze

      TARGET_WORDS = "a PagerDuty service, by its name or id, whose escalation policy pages whoever is on call".freeze
      PAGES_WORDS = "a service, whose escalation policy pages whoever is on call".freeze
      SYNC_TOOLS = [ MANAGE, BROWSE_INCIDENTS, BROWSE_SERVICES ].freeze
      ON_CALL_TOOL = "browse_schedules".freeze
      ALERT_SOURCE = AlertSource::PROVIDER_PAGERDUTY
      # PagerDuty's ids are seven or more capital letters and digits, such as PF9KMXH.
      ID = /\AP[A-Z0-9]{5,}\z/

      def page(title:, details:, target:, key:)
        service = service_for(target)
        arguments = { "action" => "create", "service" => service["id"], "title" => title, "incident_key" => key }
        incident = through(MANAGE, arguments, "raise a PagerDuty incident") do
          api.create_incident(service_id: service["id"], title: title, details: details, incident_key: key)
        end
        Paging::Raised.new(external_id: incident["id"].to_s, reference: incident["incident_number"] && "##{incident['incident_number']}",
                           url: incident["html_url"])
      rescue PagerdutyApi::Error => error
        raise Paging::Failed, Sentence.join("PagerDuty did not raise the incident", error.message)
      end

      def acknowledge(external_id, key: nil) = change_status(external_id, PagerdutyApi::STATUS_ACKNOWLEDGED, "acknowledge")

      def resolve(external_id, key: nil) = change_status(external_id, PagerdutyApi::STATUS_RESOLVED, "resolve")

      def knows?(external_id)
        through(BROWSE_INCIDENTS, { "action" => "get", "incident" => external_id }, "read the incident") { api.incident(external_id) }.present?
      rescue PagerdutyApi::Error => error
        raise Paging::Failed, Sentence.join("PagerDuty did not answer for incident #{external_id}", error.message) unless error.is_a?(NotFound)

        false
      end

      def on_call
        listed = through(ON_CALL_TOOL, { "action" => "list_oncalls" }, "read who is on call") { api.on_calls }
        listed.sort_by { |entry| entry["escalation_level"].to_i }.filter_map do |entry|
          user = entry["user"] || {}
          next if user["email"].blank? && user["summary"].blank?

          Paging::OnCall.new(name: user["name"] || user["summary"], email: user["email"], covers: covers(entry))
        end.uniq
      rescue PagerdutyApi::Error => error
        raise Paging::Failed, Sentence.join("PagerDuty did not say who is on call", error.message)
      end

      private

      def api = @api ||= PagerdutyApi.new(Credentials.headers_for(@environment_row), region: settings.region&.key)

      def change_status(external_id, status, verb)
        arguments = { "action" => "update", "incident" => external_id, "status" => status }
        through(MANAGE, arguments, "#{verb} PagerDuty incident #{external_id}") { api.update_status(external_id, status: status) }
        nil
      rescue PagerdutyApi::Error => error
        raise Paging::Failed, Sentence.join("PagerDuty did not #{verb} incident #{external_id}", error.message)
      end

      # A service by its id, or the one service whose name is the target. Several or none is Failed with their names.
      def service_for(target)
        wanted = target.to_s.strip
        raise Paging::Failed, "Name the PagerDuty service to page." if wanted.empty?

        if wanted.match?(ID)
          return through(BROWSE_SERVICES, { "action" => "get", "service" => wanted }, "read service #{wanted}") { api.service(wanted) }
        end

        found = through(BROWSE_SERVICES, { "action" => "list", "query" => wanted }, "find service #{wanted}") { api.services(query: wanted) }
        exact = found.select { |service| service["name"].to_s.casecmp?(wanted) }
        matches = exact.presence || found
        return matches.first if matches.one?

        raise Paging::Failed, "PagerDuty has no service called #{wanted}." if matches.empty?

        raise Paging::Failed, "Several PagerDuty services match #{wanted}: #{matches.map { |service| service['name'] }.to_sentence}. Name one."
      end

      def covers(entry)
        schedule = entry.dig("schedule", "summary")
        policy = entry.dig("escalation_policy", "summary")
        level = entry["escalation_level"]
        [ ("#{schedule} schedule" if schedule), ("level #{level} of #{policy}" if policy && level) ].compact.join(", ").presence
      end
    end
  end
end
