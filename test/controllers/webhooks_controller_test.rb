require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    @webhook = webhooks(:active_webhook)

    sign_in(@user, @workspace)
  end

  # Authentication

  test "redirects to login when not authenticated" do
    ApplicationController.any_instance.unstub(:current_user)
    ApplicationController.any_instance.unstub(:current_workspace)
    ApplicationController.any_instance.unstub(:user_signed_in?)
    post webhooks_url, params: { webhook: { name: "Test", url: "https://example.com" } }
    assert_response :redirect
    assert_redirected_to login_path
  end

  # Create

  test "creates a new webhook" do
    assert_difference -> { Webhook.count }, 1 do
      post webhooks_url, params: {
        webhook: {
          name: "New Test Hook",
          url: "https://example.com/new-hook",
          subscribed_events: [ "incident.created", "incident.resolved" ]
        }
      }
    end

    assert_response :redirect
    webhook = Webhook.find_by!(name: "New Test Hook")
    assert_equal @workspace, webhook.workspace
    assert_not_nil webhook.signing_secret
    assert webhook.active?
  end

  # Update

  test "updates webhook name" do
    patch webhook_url(@webhook), params: {
      webhook: { name: "Updated Name" }
    }
    assert_response :redirect
    assert_equal "Updated Name", @webhook.reload.name
  end

  # Destroy

  test "destroys webhook" do
    assert_difference -> { Webhook.count }, -1 do
      delete webhook_url(@webhook)
    end
    assert_response :redirect
  end

  # Activate / deactivate

  test "activates an inactive webhook" do
    inactive = webhooks(:inactive_webhook)
    post activate_webhook_url(inactive)
    assert_response :redirect
    assert inactive.reload.active?
  end

  test "deactivates an active webhook" do
    post deactivate_webhook_url(@webhook)
    assert_response :redirect
    assert_not @webhook.reload.active?
  end

  # Test delivery

  test "sends test delivery" do
    assert_difference -> { WebhookDelivery.count }, 1 do
      post test_webhook_url(@webhook)
    end
    assert_response :redirect
  end

  test "test delivery finds a subscribed event from any incident, not just the most recently active one" do
    most_recent_event = incident_events(:inc1_lead_assigned)
    resolved_event = incident_events(:inc3_resolved)

    assert_not_equal IncidentEvent::INCIDENT_RESOLVED, most_recent_event.event_type
    assert_not_equal resolved_event.incident, most_recent_event.incident
    assert resolved_event.created_at < most_recent_event.created_at

    webhook = Webhook.create!(
      workspace: @workspace,
      name: "Resolved Only",
      url: "https://example.com/test",
      subscribed_events: [ IncidentEvent::INCIDENT_RESOLVED ],
      active: true
    )

    assert_difference -> { WebhookDelivery.count }, 1 do
      post test_webhook_url(webhook)
    end
    assert_response :redirect

    delivery = webhook.webhook_deliveries.last
    assert_equal resolved_event, delivery.incident_event
    assert_equal IncidentEvent::INCIDENT_RESOLVED, delivery.event_type
  end

  test "test delivery reports no match when the workspace has no subscribed event" do
    webhook = Webhook.create!(
      workspace: @workspace,
      name: "Canceled Only",
      url: "https://example.com/test",
      subscribed_events: [ IncidentEvent::INCIDENT_CANCELED ],
      active: true
    )

    assert_no_difference -> { WebhookDelivery.count } do
      post test_webhook_url(webhook)
    end
    assert_response :redirect
    assert_equal "No matching events found to test with", flash[:alert]
  end

  test "test delivery ignores events from other workspaces" do
    other_workspace_event = incident_events(:ws2_inc1_created)
    assert_not_equal @workspace, other_workspace_event.incident.workspace
    assert other_workspace_event.created_at > incident_events(:inc1_created).created_at

    webhook = Webhook.create!(
      workspace: @workspace,
      name: "Created Only",
      url: "https://example.com/test",
      subscribed_events: [ IncidentEvent::INCIDENT_CREATED ],
      active: true
    )

    assert_difference -> { WebhookDelivery.count }, 1 do
      post test_webhook_url(webhook)
    end

    delivery = webhook.webhook_deliveries.last
    assert_equal @workspace, delivery.incident_event.incident.workspace
  end

  # Sample payload

  test "returns sample payload info for valid event type" do
    get sample_payload_webhooks_url, params: { event_type: "incident.created" }
    assert_response :success
  end

  test "returns error for invalid event type" do
    get sample_payload_webhooks_url, params: { event_type: "invalid.event" }
    assert_response :unprocessable_entity
  end

  # Replay

  test "replay creates a new delivery against the same webhook + event" do
    original = webhook_deliveries(:errored_delivery)

    assert_difference -> { @webhook.webhook_deliveries.count }, 1 do
      post replay_webhook_delivery_url(@webhook, original)
    end

    assert_response :redirect
    replay = @webhook.webhook_deliveries.where(incident_event_id: original.incident_event_id).order(:created_at).last
    assert_equal original.event_type, replay.event_type
    assert_equal "pending", replay.state
  end

  test "replay sends the original bytes rather than re-rendering a drifted event" do
    original = webhook_deliveries(:errored_delivery)
    original.update!(signed_payload: { data: { name: "As it was sent" } }.to_json)

    post replay_webhook_delivery_url(@webhook, original)

    replay = @webhook.webhook_deliveries.where(incident_event_id: original.incident_event_id).order(:created_at).last
    assert_equal original.signed_payload, replay.signed_payload
  end

  test "a member cannot replay a delivery" do
    sign_in(users(:bob), @workspace)
    original = webhook_deliveries(:errored_delivery)

    assert_no_difference -> { WebhookDelivery.count } do
      post replay_webhook_delivery_url(@webhook, original)
    end

    assert_redirected_to dashboard_path
  end

  test "replay cannot reach a webhook from another workspace" do
    other_webhook = webhooks(:workspace_two_webhook)
    original = webhook_deliveries(:errored_delivery)

    assert_no_difference -> { WebhookDelivery.count } do
      post replay_webhook_delivery_url(other_webhook, original)
    end
  end

  # Workspace scoping

  test "does not find webhook from different workspace" do
    other_webhook = webhooks(:workspace_two_webhook)
    assert_raises(ActiveRecord::RecordNotFound) do
      @workspace.webhooks.find(other_webhook.id)
    end
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
