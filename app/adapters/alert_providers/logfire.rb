module AlertProviders
  # Pydantic Logfire's webhook channel in its Raw Data format. Logfire's docs do not publish the body, so the shape is a
  # delivery Logfire sent, captured in its own issue tracker (pydantic/logfire#2180): alert_name, description,
  # project_name, n_rows, errors and links, with links.alert the alert's page for that run (/alerts/<id>?alertRunId=<run>).
  # An alert's query returning rows means trouble, so rows fire and no rows resolve, which Logfire sends when the alert
  # notifies on the query starting or stopping to have results. A query Logfire could not run fires too, with its errors,
  # since an alert that cannot run watches nothing. Keyed on the alert's id in that link. The channel sends no header, so
  # the token is the last segment of the source's address.
  class Logfire < Base
    LABEL = "Logfire".freeze
    SECRET_IN_ADDRESS = true
    ALERT_IN_LINK = %r{/alerts/([^/?#]+)}
    SETUP_STEPS = [
      "In Logfire, open the alert, and under Send notifications to, choose Add channel.",
      "Name the channel, choose Raw Data as its type and paste this URL. It holds the source's secret, so anyone with " \
      "it can send alerts here. Paste it nowhere else.",
      "Send a test alert, which Logfire needs to succeed before it creates the channel, then create it and tick it for " \
      "each alert that should reach Firefight.",
      "Set Fire when to the query starts or stops having results, so the alert resolves here when the query stops " \
      "returning rows."
    ].freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(address_secret(headers), source)

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash) && payload["alert_name"].present? && payload["n_rows"].is_a?(Integer)

      alert_link = payload.dig("links", "alert").to_s
      alert_id = alert_link[ALERT_IN_LINK, 1]
      fingerprint = alert_id ? "alert:#{alert_id}" : [ "alert", payload["project_name"], payload["alert_name"] ].compact.join(":")
      run_id = run_id(alert_link)
      errors = errors_text(payload["errors"])

      fields = {
        "external_id" => run_id ? "run:#{run_id}" : [ fingerprint, payload["timestamp"] ].compact.join(":"),
        "fingerprint" => fingerprint,
        "status" => payload["n_rows"].positive? || errors ? Alert::STATUS_FIRING : Alert::STATUS_RESOLVED,
        "title" => payload["alert_name"],
        "description" => [ payload["description"], rows_text(payload["n_rows"]), errors ].compact_blank.join("\n"),
        "service" => payload["project_name"],
        "url" => alert_link
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.run_id(link)
      Rack::Utils.parse_query(URI.parse(link).query.to_s)["alertRunId"].presence
    rescue URI::InvalidURIError
      nil
    end

    def self.rows_text(count) = count.positive? ? "The query returned #{count} #{'row'.pluralize(count)}." : nil

    def self.errors_text(errors)
      return if errors.blank?

      "Logfire could not run the query. #{errors.is_a?(String) ? errors : errors.to_json}"
    end
  end
end
