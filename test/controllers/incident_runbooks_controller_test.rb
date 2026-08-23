require "test_helper"

class IncidentRunbooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @runbook = @workspace.runbooks.create!(name: "Database outage")
    @runbook.runbook_steps.create!(title: "Check the pool", position: 1)
    sign_in(@member.user, @workspace)
    stub_post_message
  end

  test "attaching a runbook by hand posts it and confirms" do
    assert_difference "@incident.incident_runbooks.count", 1 do
      post incident_runbooks_path(@incident), params: { slug: @runbook.slug }
    end

    assert_redirected_to incident_path(@incident)
    assert_equal "Database outage was attached.", flash[:notice]
  end

  test "attaching the same runbook twice leaves one attachment" do
    post incident_runbooks_path(@incident), params: { slug: @runbook.slug }

    assert_no_difference "@incident.incident_runbooks.count" do
      post incident_runbooks_path(@incident), params: { slug: @runbook.slug }
    end
  end

  test "an unknown slug is refused rather than silently doing nothing" do
    post incident_runbooks_path(@incident), params: { slug: "not_a_runbook" }

    assert_redirected_to incident_path(@incident)
    assert_equal "That runbook is no longer available.", flash[:alert]
  end

  test "the incident page offers only runbooks that are not attached yet" do
    get incident_path(@incident), headers: inertia_headers
    assert_response :success
    offered = inertia_props["attachableRunbooks"].map { |runbook| runbook["slug"] }
    assert_includes offered, @runbook.slug

    post incident_runbooks_path(@incident), params: { slug: @runbook.slug }

    get incident_path(@incident), headers: inertia_headers
    offered = inertia_props["attachableRunbooks"].map { |runbook| runbook["slug"] }
    assert_not_includes offered, @runbook.slug
  end
end
