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
