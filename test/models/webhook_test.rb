require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  test "every subscribable event renders a payload" do
    Webhook::SUBSCRIBABLE_EVENTS.each do |event_type|
      template = Webhook::SUBSCRIBABLE_EVENT_TEMPLATES.fetch(event_type)
      assert File.exist?(Rails.root.join("app/views/#{template}.json.jbuilder")),
             "#{event_type} is subscribable but has no payload template"
    end
  end

  test "belongs to workspace" do
    webhook = webhooks(:active_webhook)
    assert_instance_of Workspace, webhook.workspace
    assert_equal workspaces(:slack_workspace_one), webhook.workspace
  end

  test "has one delinquency tracker" do
    webhook = webhooks(:active_webhook)
    assert_instance_of WebhookDelinquencyTracker, webhook.webhook_delinquency_tracker
  end

  test "requires name" do
    webhook = Webhook.new(workspace: workspaces(:slack_workspace_one), url: "https://example.com")
    assert_not webhook.valid?
    assert_includes webhook.errors[:name], "can't be blank"
  end

  test "requires valid url with http or https scheme" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "ftp://example.com"
    )
    assert_not webhook.valid?
    assert_includes webhook.errors[:url], "must use http or https"
  end

  test "rejects invalid url" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "not a url"
    )
    assert_not webhook.valid?
    assert webhook.errors[:url].any?
  end

  test "accepts valid https url" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "https://example.com/webhooks"
    )
    assert webhook.valid?
  end

  test "accepts valid http url" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "http://example.com/webhooks"
    )
    assert webhook.valid?
  end

  test "auto-generates signing_secret on create" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "New Hook",
      url: "https://example.com/hook"
    )
    assert_not_nil webhook.signing_secret
    assert_equal 32, webhook.signing_secret.length
  end

  test "normalizes subscribed_events to only permitted values" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "https://example.com",
      subscribed_events: [ "incident.created", "invalid.event", "incident.resolved" ]
    )
    assert_equal [ "incident.created", "incident.resolved" ], webhook.subscribed_events
  end

  test "normalizes subscribed_events deduplicates" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "https://example.com",
      subscribed_events: [ "incident.created", "incident.created" ]
    )
    assert_equal [ "incident.created" ], webhook.subscribed_events
  end

  test "strips whitespace from url" do
    webhook = Webhook.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      url: "  https://example.com  "
    )
    assert_equal "https://example.com", webhook.url
  end

  test "active scope returns only active webhooks" do
    active = Webhook.active.where(workspace: workspaces(:slack_workspace_one))
    assert_includes active, webhooks(:active_webhook)
    assert_not_includes active, webhooks(:inactive_webhook)
  end

  test "triggered_by scope finds webhooks subscribed to event type" do
    matches = Webhook.triggered_by(IncidentEvent::INCIDENT_CREATED)
      .where(workspace: workspaces(:slack_workspace_one))
    assert_includes matches, webhooks(:active_webhook)
    assert_not_includes matches, webhooks(:inactive_webhook)
  end

  test "triggered_by scope excludes webhooks not subscribed to event type" do
    matches = Webhook.triggered_by(IncidentEvent::LEAD_ASSIGNED)
      .where(workspace: workspaces(:slack_workspace_one))
    assert_not_includes matches, webhooks(:active_webhook)
  end

  test "deactivate! sets active to false" do
    webhook = webhooks(:active_webhook)
    webhook.deactivate!
    assert_not webhook.reload.active?
  end

  test "activate! sets active to true" do
    webhook = webhooks(:inactive_webhook)
    webhook.activate!
    assert webhook.reload.active?
  end

  test "creates delinquency tracker on create" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "New Hook",
      url: "https://example.com/hook"
    )
    assert_not_nil webhook.webhook_delinquency_tracker
    assert_equal 0, webhook.webhook_delinquency_tracker.consecutive_failures_count
  end

  test "latest_subscribed_event is the newest event of a subscribed type, from any incident" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one), name: "Resolved only",
      url: "https://example.com/test", subscribed_events: [ IncidentEvent::INCIDENT_RESOLVED ]
    )

    assert_equal incident_events(:inc3_resolved), webhook.latest_subscribed_event
  end

  test "latest_subscribed_event never crosses into another workspace" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one), name: "Created only",
      url: "https://example.com/test", subscribed_events: [ IncidentEvent::INCIDENT_CREATED ]
    )
    other = incident_events(:ws2_inc1_created)
    assert other.created_at > incident_events(:inc1_created).created_at

    assert_equal workspaces(:slack_workspace_one), webhook.latest_subscribed_event.incident.workspace
  end

  test "queue_test_delivery! queues one delivery of the newest subscribed event" do
    webhook = webhooks(:active_webhook)

    delivery = assert_difference -> { webhook.webhook_deliveries.count }, 1 do
      webhook.queue_test_delivery!
    end

    assert_equal webhook.latest_subscribed_event, delivery.incident_event
    assert_equal delivery.incident_event.event_type, delivery.event_type
    assert delivery.pending?
  end

  test "test_blocked_reason names why there is nothing to send, and queue_test_delivery! refuses with it" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one), name: "Canceled only",
      url: "https://example.com/test", subscribed_events: [ IncidentEvent::INCIDENT_CANCELED ]
    )

    assert_match(/No matching events found to test with/, webhook.test_blocked_reason)
    error = assert_raises(Webhook::TestBlocked) { webhook.queue_test_delivery! }
    assert_equal webhook.test_blocked_reason, error.message
  end

  test "test_blocked_reason is nil when a subscribed event exists" do
    assert_nil webhooks(:active_webhook).test_blocked_reason
  end
end
