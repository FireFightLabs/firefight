require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  # Subscribable events

  # The dashboard's list is a hand-maintained copy of this constant, and it
  # drifted by five events before anyone noticed. An event the server delivers
  # but nobody can tick is a feature the customer does not have.
  EVENTS_FILE = Rails.root.join("app/frontend/pages/settings/lib/webhook-events.ts")

  test "the dashboard offers exactly the events the server accepts" do
    offered = EVENTS_FILE.read.scan(/value: "([a-z._]+)"/).flatten

    assert_equal Webhook::SUBSCRIBABLE_EVENTS, offered,
                 "webhook-events.ts has drifted from Webhook::SUBSCRIBABLE_EVENTS"
  end

  test "every subscribable event renders a payload" do
    Webhook::SUBSCRIBABLE_EVENTS.each do |event_type|
      template = Webhook::SUBSCRIBABLE_EVENT_TEMPLATES.fetch(event_type)
      assert File.exist?(Rails.root.join("app/views/#{template}.json.jbuilder")),
             "#{event_type} is subscribable but has no payload template"
    end
  end

  # Associations

  test "belongs to workspace" do
    webhook = webhooks(:active_webhook)
    assert_instance_of Workspace, webhook.workspace
    assert_equal workspaces(:slack_workspace_one), webhook.workspace
  end

  test "has one delinquency tracker" do
    webhook = webhooks(:active_webhook)
    assert_instance_of WebhookDelinquencyTracker, webhook.webhook_delinquency_tracker
  end

  # Validations

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

  # Token generation

  test "auto-generates signing_secret on create" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "New Hook",
      url: "https://example.com/hook"
    )
    assert_not_nil webhook.signing_secret
    assert_equal 32, webhook.signing_secret.length
  end

  # Normalization

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

  # Scopes

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

  # Activate / deactivate

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

  # Delinquency tracker auto-creation

  test "creates delinquency tracker on create" do
    webhook = Webhook.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "New Hook",
      url: "https://example.com/hook"
    )
    assert_not_nil webhook.webhook_delinquency_tracker
    assert_equal 0, webhook.webhook_delinquency_tracker.consecutive_failures_count
  end
end
