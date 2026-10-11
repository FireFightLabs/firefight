module AlertProviders
  # Honeybadger's Webhook integration (docs.honeybadger.io, Webhook integration and its payload pages). An error fires
  # when it occurs, passes its rate or is unresolved, and resolves when it is resolved, keyed on the fault. An uptime
  # check fires when the site is down and resolves when it is up, keyed on the site, and a check in fires when it is
  # missing and resolves when it reports again. Every other event, such as an assignment, a comment or a deploy, is
  # accepted and ignored. Honeybadger signs nothing, and sends the bearer token set on the integration.
  class Honeybadger < Base
    LABEL = "Honeybadger".freeze
    FAULT_FIRING = %w[occurred rate_exceeded unresolved].freeze
    FAULT_RESOLVED = "resolved".freeze
    SITE_FIRING = "down".freeze
    SITE_RESOLVED = "up".freeze
    CHECK_IN_FIRING = "check_in_missing".freeze
    CHECK_IN_RESOLVED = "check_in_reporting".freeze
    RESOLVED_EVENTS = [ FAULT_RESOLVED, SITE_RESOLVED, CHECK_IN_RESOLVED ].freeze
    ALERT_EVENTS = (FAULT_FIRING + [ SITE_FIRING, CHECK_IN_FIRING ] + RESOLVED_EVENTS).freeze
    SETUP_STEPS = [
      "In Honeybadger, open the project's settings, then Alerts & Integrations, and choose Webhook.",
      "Paste this URL as the URL.",
      "Paste the token into the Bearer token field and save.",
      "Firefight turns errors that occur, are unresolved or pass their rate, uptime checks going down and missing check " \
      "ins into alerts, and resolves them when Honeybadger sends resolved, up or reporting. It accepts and ignores other events."
    ].freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(bearer_token(headers), source)

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash)

      fields = case payload["event"]
      when *FAULT_FIRING, FAULT_RESOLVED then fault_fields(payload)
      when SITE_FIRING, SITE_RESOLVED then site_fields(payload)
      when CHECK_IN_FIRING, CHECK_IN_RESOLVED then check_in_fields(payload)
      end
      return [] if fields.nil? || fields["fingerprint"].blank?

      fields["status"] = RESOLVED_EVENTS.include?(payload["event"]) ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING
      fields["service"] ||= payload.dig("project", "name")
      [ item(fields.compact_blank, payload) ]
    end

    def self.ignored?(payload)
      payload.is_a?(Hash) && payload["event"].present? && ALERT_EVENTS.exclude?(payload["event"])
    end

    def self.fault_fields(payload)
      fault = payload["fault"]
      return unless fault.is_a?(Hash) && fault["id"].present?

      {
        "external_id" => payload.dig("notice", "id")&.then { |id| "notice:#{id}" },
        "fingerprint" => "fault:#{fault['id']}",
        "title" => [ fault["klass"], fault["message"] ].compact_blank.join(": ").truncate(255).presence || payload["message"],
        "description" => payload["message"],
        "environment" => fault["environment"],
        "url" => payload.dig("notice", "url").presence || fault["url"]
      }
    end

    def self.site_fields(payload)
      site = payload["site"]
      return unless site.is_a?(Hash) && site["id"].present?

      {
        "fingerprint" => "site:#{site['id']}",
        "title" => "#{site['name'].presence || site['url']} is down",
        "description" => [ payload["message"], payload.dig("outage", "reason") ].compact_blank.join("\n"),
        "url" => site["details_url"].presence || payload.dig("outage", "details_url")
      }
    end

    def self.check_in_fields(payload)
      check_in = payload["check_in"]
      return unless check_in.is_a?(Hash) && check_in["id"].present?

      {
        "fingerprint" => "check_in:#{check_in['id']}",
        "title" => "#{check_in['name'].presence || check_in['id']} is missing",
        "description" => payload["message"],
        "url" => check_in["details_url"]
      }
    end
  end
end
