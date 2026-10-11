module AlertProviders
  # Mixpanel's alert Notification Webhook (docs.mixpanel.com, Alerts, Webhook Alerts). Mixpanel posts when an alert
  # triggers, at most once a check, and never when it clears. Each trigger is therefore its own firing alert, since one
  # alert per Mixpanel alert would stay open for good and swallow every later trigger. Mixpanel's only way to
  # authenticate is HTTP Basic auth, so the token is the webhook's password.
  class Mixpanel < Base
    LABEL = "Mixpanel".freeze
    SETUP_STEPS = [
      "In Mixpanel, open Project Settings, then Alerts, and choose Manage Webhooks. Click Add Webhook.",
      "Paste this URL as the URL. Enter any user name, such as firefight, and paste the token as the password. Click " \
      "Test connection, then Submit.",
      "In each alert, choose the webhook under Notify, via Webhook, and save. Mixpanel sends nothing when an alert " \
      "clears, so each trigger arrives as a new alert."
    ].freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(basic_password(headers), source)

    def self.normalize(payload, source:, headers: {})
      alert = payload.is_a?(Hash) ? payload["alert"] : nil
      return [] unless alert.is_a?(Hash) && alert["id"].present?

      fields = {
        "external_id" => [ alert["id"], alert["fired_at"] ].compact.join(":"),
        "fingerprint" => [ "alert", alert["id"], alert["fired_at"] ].compact.join(":"),
        "status" => Alert::STATUS_FIRING,
        "title" => alert["name"].to_s,
        "description" => description_of(payload),
        "service" => alert["project_name"],
        "url" => payload.dig("links", "report_url").presence || payload.dig("report", "url")
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.description_of(payload)
      condition = payload["condition"].is_a?(Hash) ? payload["condition"] : {}
      value = condition["formatted_value"].presence || condition["current_value"]
      [
        ("#{payload.dig('report', 'name')} is #{condition['sentence']}" if condition["sentence"].present?),
        ("Current value #{value}" if value.present?)
      ].compact.join(". ").presence
    end
  end
end
