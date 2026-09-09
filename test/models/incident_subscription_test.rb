require "test_helper"

class IncidentSubscriptionTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "the first subscribe subscribes and the second says so, leaving one row" do
    assert_equal Incident::Subscriptions::SUBSCRIBED, @incident.subscribe!(@alice)
    assert_equal Incident::Subscriptions::ALREADY_SUBSCRIBED, @incident.subscribe!(@alice)

    assert_equal 1, @incident.incident_subscriptions.where(workspace_membership: @alice).count
    assert @incident.subscribed?(@alice)
  end

  test "unsubscribing removes the row, and unsubscribing again changes nothing" do
    @incident.subscribe!(@alice)

    assert_equal Incident::Subscriptions::UNSUBSCRIBED, @incident.unsubscribe!(@alice)
    assert_not @incident.subscribed?(@alice)

    assert_no_difference "IncidentSubscription.count" do
      assert_equal Incident::Subscriptions::UNSUBSCRIBED, @incident.unsubscribe!(@alice)
    end
  end

  test "each state has a finished sentence naming the incident" do
    [ Incident::Subscriptions::SUBSCRIBED, Incident::Subscriptions::ALREADY_SUBSCRIBED, Incident::Subscriptions::UNSUBSCRIBED ].each do |state|
      sentence = @incident.subscription_notice(state)
      assert_includes sentence, @incident.identifier
      assert_match(/\.\z/, sentence)
      assert_no_match(/[;\u2014]/, sentence)
    end
  end

  test "subscriber_platform_user_ids names every subscriber by their platform id" do
    @incident.subscribe!(@alice)
    @incident.subscribe!(@bob)

    assert_equal [ @alice.platform_user_id, @bob.platform_user_id ].sort, @incident.subscriber_platform_user_ids.sort
  end

  test "a subscription belongs to the incident's workspace and dies with the incident" do
    @incident.subscribe!(@alice)
    subscription = @incident.incident_subscriptions.find_by!(workspace_membership: @alice)
    assert_equal @incident.workspace, subscription.workspace

    @incident.destroy!
    assert_not IncidentSubscription.exists?(subscription.id)
  end
end
