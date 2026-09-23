require "test_helper"

class Investigation::IncidentSeedTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = investigation_for(@incident)
  end

  test "the pack names the incident, its state and who is on it" do
    facts = @investigation.build_seed_pack!["incident"]

    assert_equal "INC-001", facts["identifier"]
    assert_equal "Database connection pool exhausted", facts["name"]
    assert_equal "Critical", facts["severity"]
    assert_equal "Investigating", facts["status"]
    assert_nil facts["lead"], "this incident has no lead, and the pack says so rather than guessing"
    assert_equal [ { "role" => "Communications Lead",
                     "member" => { "name" => workspace_memberships(:bob_workspace_one).display_name } } ],
                 facts["roles"]
  end

  test "the lead is named separately from the other roles" do
    investigation = investigation_for(incidents(:active_major_ws1))

    facts = investigation.build_seed_pack!["incident"]

    assert_equal workspace_memberships(:bob_workspace_one).display_name, facts["lead"]["name"]
    assert_not facts["lead"].key?("platform_user_id"), "the pack carries no platform shaped value"
    assert_empty facts["roles"], "the lead is not repeated in the role list"
  end

  test "alerts arrive oldest first with their provider fields intact" do
    source = alert_source("Grafana")
    attach_alert(source, fingerprint: "cpu", fields: { "title" => "CPU saturated", "service" => "checkout" },
                 received_at: 20.minutes.ago)
    attach_alert(source, fingerprint: "pool", fields: { "title" => "Pool exhausted" }, received_at: 40.minutes.ago)

    alerts = @investigation.build_seed_pack!["alerts"]

    assert_equal [ "Pool exhausted", "CPU saturated" ], alerts.map { |alert| alert["title"] }
    assert_equal "Grafana", alerts.first["source"]
    assert_equal "checkout", alerts.last["fields"]["service"]
    assert_equal 0, @investigation.seed_pack["alerts_held_back"]
  end

  test "a flood of alerts is capped and the pack counts what it left out" do
    source = alert_source("Grafana")
    (Investigation::IncidentSeed::ALERT_LIMIT + 3).times do |index|
      attach_alert(source, fingerprint: "flood-#{index}", fields: { "title" => "Alert #{index}" },
                   received_at: index.minutes.ago)
    end

    pack = @investigation.build_seed_pack!

    assert_equal Investigation::IncidentSeed::ALERT_LIMIT, pack["alerts"].size
    assert_equal 3, pack["alerts_held_back"]
  end

  test "attached runbooks are listed by name" do
    runbook = @workspace.runbooks.create!(name: "Pool exhaustion triage", slug: "pool-triage", position: 1,
                                          summary: "What to check when connections run out.")
    @incident.incident_runbooks.create!(workspace: @workspace, runbook: runbook)

    runbooks = @investigation.build_seed_pack!["runbooks"]

    assert_equal [ { "name" => "Pool exhaustion triage",
                     "summary" => "What to check when connections run out." } ], runbooks
  end

  test "a past incident that fired the same alert is included with its finding" do
    source = alert_source("Grafana")
    attach_alert(source, fingerprint: "pool", fields: { "title" => "Pool exhausted" })
    past = incidents(:resolved_minor_ws1)
    attach_alert(source, fingerprint: "pool", incident: past, fields: { "title" => "Pool exhausted" },
                 status: Alert::STATUS_RESOLVED)
    record_finding(past, "The connection pool was sized for one worker.")

    past_incidents = @investigation.build_seed_pack!["past_incidents"]

    assert_equal [ "INC-003" ], past_incidents.map { |entry| entry["identifier"] }
    assert_equal "The connection pool was sized for one worker.", past_incidents.first["finding"]
  end

  test "a past incident with the same fingerprint from another source is not a match" do
    attach_alert(alert_source("Grafana"), fingerprint: "pool", fields: { "title" => "Pool exhausted" })
    attach_alert(alert_source("Datadog"), fingerprint: "pool", incident: incidents(:resolved_minor_ws1),
                 fields: { "title" => "Pool exhausted" }, status: Alert::STATUS_RESOLVED)

    assert_empty @investigation.build_seed_pack!["past_incidents"],
                 "a fingerprint only means the same alert within one source"
  end

  test "an incident still open is not offered as a past incident" do
    source = alert_source("Grafana")
    attach_alert(source, fingerprint: "pool", fields: { "title" => "Pool exhausted" })
    attach_alert(source, fingerprint: "pool", incident: incidents(:active_major_ws1),
                 fields: { "title" => "Pool exhausted" }, status: Alert::STATUS_RESOLVED)

    assert_empty @investigation.build_seed_pack!["past_incidents"],
                 "an incident nobody has resolved teaches nothing about how this one ends"
  end

  test "an incident with nothing attached still gets a pack it can reason from" do
    pack = @investigation.build_seed_pack!

    assert_empty pack["alerts"]
    assert_empty pack["runbooks"]
    assert_empty pack["past_incidents"]
    assert_equal "INC-001", pack["incident"]["identifier"]
    assert pack["gathered_at"].present?, "the pack records when it was true"
  end

  test "the pack is stored on the investigation, not recomputed per reader" do
    @investigation.build_seed_pack!

    assert_equal @investigation.reload.seed_pack, @investigation.seed_pack
    assert_equal "INC-001", @investigation.reload.seed_pack["incident"]["identifier"]
  end

  test "the services on the incident are named with where each keeps its code" do
    service_type = catalog_types(:service_ws1)
    service_type.catalog_attribute_definitions.create!(
      name: "Repository", slug: "repository", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9
    )
    service = catalog_entries(:auth_service)
    service.update!(attributes: service.entry_attributes.merge("repository" => "https://github.com/acme/auth.git"))
    @incident.update!(custom_fields: { "affected_services" => [ service.id ] })

    services = @investigation.build_seed_pack!["services"]

    assert_equal [ { "name" => "Auth Service", "repository" => "acme/auth" } ], services
  end

  private

  def investigation_for(incident)
    @workspace.investigations.create!(
      subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
  end

  def alert_source(name)
    @workspace.alert_sources.create!(name: name, provider: AlertSource::PROVIDER_GENERIC)
  end

  def attach_alert(source, fingerprint:, fields:, incident: nil, received_at: 10.minutes.ago,
                   status: Alert::STATUS_FIRING)
    source.alerts.create!(
      workspace: @workspace, incident: incident || @incident, external_id: SecureRandom.hex(4),
      fingerprint: fingerprint, fields: fields, status: status,
      received_at: received_at, last_seen_at: received_at
    )
  end

  def record_finding(incident, summary)
    run = @workspace.investigations.create!(
      subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      status: Investigation::STATUS_SUCCEEDED
    )
    run.create_finding!(summary: summary)
  end
end
