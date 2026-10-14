require "test_helper"

class Webhooks::PayloadRendererTest < ActiveSupport::TestCase
  setup do
    @event = incident_events(:inc1_created)
    @delivery_id = SecureRandom.uuid
  end

  test "renders incident_created payload with envelope" do
    json = Webhooks::PayloadRenderer.render(@event, delivery_id: @delivery_id)
    payload = JSON.parse(json)

    assert_equal @delivery_id, payload["id"]
    assert_equal "incident.created", payload["event_type"]
    assert_equal @event.incident.workspace_id, payload["workspace_id"]
    assert_not_nil payload["occurred_at"]
    assert_not_nil payload["data"]["incident"]
    assert_equal @event.incident.identifier, payload["data"]["incident"]["identifier"]
    assert_equal @event.incident.name, payload["data"]["incident"]["name"]
  end

  test "renders incident payload with status and severity" do
    json = Webhooks::PayloadRenderer.render(@event, delivery_id: @delivery_id)
    payload = JSON.parse(json)

    incident_data = payload["data"]["incident"]
    assert_not_nil incident_data["status"]
    assert_not_nil incident_data["status"]["name"]
    assert_not_nil incident_data["severity"]
    assert_not_nil incident_data["severity"]["name"]
  end

  test "renders actor when event has user" do
    json = Webhooks::PayloadRenderer.render(@event, delivery_id: @delivery_id)
    payload = JSON.parse(json)

    assert_not_nil payload["data"]["actor"]
    assert_not_nil payload["data"]["actor"]["name"]
    assert_not_nil payload["data"]["actor"]["email"]
  end

  test "renders incident_updated with changed_fields and changes" do
    event = incident_events(:inc1_updated)
    json = Webhooks::PayloadRenderer.render(event, delivery_id: @delivery_id)
    payload = JSON.parse(json)

    assert_equal "incident.updated", payload["event_type"]
    assert payload["data"].key?("changed_fields")
    assert payload["data"].key?("changes")
  end

  test "renders a before and after for every changed field, including the renamed ones" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: member)
    event = incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: member) do
      incident.update!(incident_status: incident_statuses(:identified_ws1), incident_severity: incident_severities(:major_ws1),
                       incident_type: incident_types(:service_outage_ws1), lead: member, name: "Checkout is down")
    end

    data = JSON.parse(Webhooks::PayloadRenderer.render(event, delivery_id: @delivery_id))["data"]

    assert_equal %w[lead name severity status type], data["changed_fields"].sort
    assert_equal data["changed_fields"].sort, data["changes"].keys.sort
    assert_equal "Investigating", data["changes"]["status"]["before"]["name"]
    assert_equal data["incident"]["status"], data["changes"]["status"]["after"]
    assert_equal incident_severities(:critical_ws1).name, data["changes"]["severity"]["before"]["name"]
    assert_equal data["incident"]["severity"], data["changes"]["severity"]["after"]
    assert_nil data["changes"]["type"]["before"]
    assert_equal data["incident"]["type"], data["changes"]["type"]["after"]
    assert_nil data["changes"]["lead"]["before"]
    assert_equal data["incident"]["lead"], data["changes"]["lead"]["after"]
    assert_equal({ "before" => "Database connection pool exhausted", "after" => "Checkout is down" }, data["changes"]["name"])
  end

  test "renders a milestone note with its kind, author and source message" do
    event = @event.incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      metadata: {
        kind: "root_cause",
        statement: "Alice identified the migration lock as the root cause",
        member_name: "Alice",
        said_at: "2026-08-25T09:00:00Z",
        message_text: "it's the migration lock",
        permalink: "https://slack.test/p1"
      }
    )

    payload = JSON.parse(Webhooks::PayloadRenderer.render(event, delivery_id: @delivery_id))

    assert_equal "milestone.noted", payload["event_type"]
    assert_equal "root_cause", payload["data"]["note"]["kind"]
    assert_equal "Alice", payload["data"]["note"]["said_by"]
    assert_equal "it's the migration lock", payload["data"]["note"]["message_text"]
    assert_equal "https://slack.test/p1", payload["data"]["note"]["permalink"]
  end

  test "a blank start is sent as postmortem.started with the postmortem and who started it" do
    incident = @event.incident
    incident.postmortem&.destroy!
    member = workspace_memberships(:alice_workspace_one)
    postmortem = Postmortem.start_blank!(incident.reload, by: member)
    event = incident.incident_events.find_by!(event_type: IncidentEvent::POSTMORTEM_STARTED)

    payload = JSON.parse(Webhooks::PayloadRenderer.render(event, delivery_id: @delivery_id))

    assert_equal "postmortem.started", payload["event_type"]
    assert_equal postmortem.id, payload["data"]["postmortem"]["id"]
    assert_equal Postmortem::STATUS_DRAFT, payload["data"]["postmortem"]["status"]
    assert_equal member.actor_display_name, payload["data"]["actor"]["name"]
  end

  test "template_for returns correct template for known event types" do
    assert_equal "webhooks/events/incident_created",
      Webhooks::PayloadRenderer.template_for(IncidentEvent::INCIDENT_CREATED)
    assert_equal "webhooks/events/incident_resolved",
      Webhooks::PayloadRenderer.template_for(IncidentEvent::INCIDENT_RESOLVED)
  end

  test "every subscribable event resolves to a template file that exists" do
    Webhook::SUBSCRIBABLE_EVENT_TEMPLATES.each_value do |template|
      path = Rails.root.join("app/views/#{template}.json.jbuilder")
      assert File.exist?(path), "missing template #{template}"
    end
  end

  test "all subscribable events have a template mapping" do
    Webhook::SUBSCRIBABLE_EVENTS.each do |event_type|
      template = Webhooks::PayloadRenderer.template_for(event_type)
      assert template.present?,
        "Event type #{event_type} should have a dedicated template"
    end
  end
end
