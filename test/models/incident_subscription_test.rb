require "test_helper"

class IncidentSubscriptionTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "subscribing twice leaves one subscription" do
    @incident.subscribe!(@alice)
    @incident.subscribe!(@alice)

    assert_equal 1, @incident.incident_subscriptions.where(workspace_membership: @alice).count
    assert @incident.subscribed?(@alice)
  end

  test "unsubscribing someone who never subscribed changes nothing" do
    assert_no_difference "IncidentSubscription.count" do
      @incident.unsubscribe!(@bob)
    end
  end

  test "toggle_subscription! flips the state and says where it landed" do
    assert @incident.toggle_subscription!(@alice)
    assert @incident.subscribed?(@alice)

    assert_not @incident.toggle_subscription!(@alice)
    assert_not @incident.subscribed?(@alice)
  end

  test "subscriber_platform_user_ids names every subscriber by their platform id" do
    @incident.subscribe!(@alice)
    @incident.subscribe!(@bob)

    assert_equal [ @alice.platform_user_id, @bob.platform_user_id ].sort, @incident.subscriber_platform_user_ids.sort
  end

  test "a subscription belongs to the incident's workspace and dies with the incident" do
    subscription = @incident.subscribe!(@alice)
    assert_equal @incident.workspace, subscription.workspace

    @incident.destroy!
    assert_not IncidentSubscription.exists?(subscription.id)
  end
end
