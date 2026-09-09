require "test_helper"

class IncidentSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    sign_in(@user, @workspace)
  end

  test "subscribing confirms with a toast and lands on the incident" do
    post incident_subscription_path(@incident)

    assert_redirected_to incident_path(@incident)
    assert_match(/subscribed to #{@incident.identifier}/, flash[:notice])
    assert @incident.subscribed?(@member)
  end

  test "unsubscribing confirms with a toast" do
    @incident.subscribe!(@member)

    delete incident_subscription_path(@incident)

    assert_redirected_to incident_path(@incident)
    assert_match(/no longer subscribed/, flash[:notice])
    assert_not @incident.subscribed?(@member)
  end

  test "the incident page says whether the viewer is subscribed and lists who is" do
    @incident.subscribe!(@member)

    get incident_path(@incident), headers: inertia_headers

    assert_response :success
    props = inertia_props
    assert_equal true, props["subscribed"]
    assert_equal [ @member.id ], props.dig("incident", "subscribers").map { |subscriber| subscriber["id"] }
  end

  test "another workspace's incident cannot be subscribed to" do
    other = incidents(:active_p0_ws2)

    post incident_subscription_path(other)

    assert_response :not_found
  end
end
