# Connections to PagerDuty and Opsgenie with the tools a page is raised and kept in step through switched on, and the
# webhook deliveries their alert sources send, so a test never reaches an on-call tool.
module PagingTestHelper
  PAGERDUTY_TOOLS = { "manage_incidents" => false, "browse_incidents" => true, "browse_services" => true, "browse_schedules" => true }.freeze

  def connect_pagerduty!(workspace, slug: "pagerduty", name: "PagerDuty")
    integration = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: Integrations::Providers::Pagerduty.key, name: name, slug: slug,
                                                 settings: { "server_url" => "https://mcp.pagerduty.com/mcp", Integration::REGION_SETTING => "us" })
    integration.integration_environments.create!(credentials: { "authorization" => "Token token=pd-key" }.to_json)
    PAGERDUTY_TOOLS.each do |tool, reads|
      integration.tools.create!(name: tool, description: tool, read_only: reads, enabled: true, params_schema: { "type" => "object" })
    end
    integration
  end

  def connect_opsgenie!(workspace, slug: "opsgenie")
    integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: Integrations::Providers::Opsgenie.key, name: "Opsgenie", slug: slug)
    row = integration.integration_environments.create!
    Integrations::Packs::Opsgenie.store_credentials!(row, Integrations::Packs::Opsgenie::API_KEY => "og-key")
    Integrations::Packs::Opsgenie.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    integration
  end

  def pagerduty_source!(workspace, name: "PagerDuty webhooks")
    AlertSource.create!(workspace: workspace, name: name, provider: AlertSource::PROVIDER_PAGERDUTY)
  end

  def opsgenie_source!(workspace, name: "Opsgenie webhooks")
    AlertSource.create!(workspace: workspace, name: name, provider: AlertSource::PROVIDER_OPSGENIE)
  end

  # A PagerDuty incident as its REST API answers one.
  def pagerduty_incident(id: "PGR0VU2", number: 42, title: "INC-001 Checkout failing")
    { "id" => id, "incident_number" => number, "title" => title, "status" => "triggered", "html_url" => "https://acme.pagerduty.com/incidents/#{id}" }
  end

  # A v3 webhook event about a PagerDuty incident, shaped as PagerDuty's own example.
  def pagerduty_event(event_type, incident_id: "PGR0VU2", incident_key: nil, agent: "user_reference", event_id: SecureRandom.uuid, note: nil)
    data = if note
      { "type" => "incident_note", "id" => "PNOTE1", "content" => note,
        "incident" => { "id" => incident_id, "type" => "incident_reference", "html_url" => "https://acme.pagerduty.com/incidents/#{incident_id}" } }
    else
      { "id" => incident_id, "type" => "incident", "number" => 42, "status" => "triggered", "title" => "INC-001 Checkout failing",
        "incident_key" => incident_key, "html_url" => "https://acme.pagerduty.com/incidents/#{incident_id}",
        "service" => { "id" => "PF9KMXH", "summary" => "Checkout", "type" => "service_reference" },
        "assignees" => [ { "id" => "PTUXL6G", "summary" => "Bob Ruiz", "type" => "user_reference" } ] }.compact
    end
    { "event" => { "id" => event_id, "event_type" => event_type, "resource_type" => "incident", "occurred_at" => Time.current.iso8601,
                   "agent" => agent && { "id" => "PLH1HKV", "summary" => "Ana Diaz", "type" => agent }, "data" => data } }
  end

  # An Opsgenie Webhook integration's post for an alert action.
  def opsgenie_action(action, alert_id: "70413a06-38d6-4c85-92b8-5ebc900d42e2", username: "bob@example.com", alias_name: nil, note: nil)
    { "action" => action, "integrationName" => "Firefight",
      "alert" => { "alertId" => alert_id, "message" => "INC-001 Checkout failing", "username" => username, "alias" => alias_name, "note" => note }.compact,
      "source" => { "name" => "", "type" => "web" } }
  end

  def deliver_alert!(source, payload)
    post "/api/v1/alerts/#{source.endpoint_path}", params: payload.to_json,
                                                    headers: { "Content-Type" => "application/json", AlertProviders::Base::TOKEN_HEADER => source.secret_token }
  end
end
