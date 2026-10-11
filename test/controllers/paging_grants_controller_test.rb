require "test_helper"

class PagingGrantsControllerTest < ActionDispatch::IntegrationTest
  include PagingTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @pagerduty = connect_pagerduty!(@workspace)
    sign_in(users(:alice), @workspace)
  end

  test "a connection's paging tools are granted to Firefight paging when they are first made, and a revoked one is not given back" do
    held = Ability::Resolver.resolve(SystemAgent.paging, @workspace)
    assert held.covers?("pagerduty.manage_incidents")
    assert held.covers?("pagerduty.browse_incidents")
    assert_not held.covers?("pagerduty.browse_schedules"), "who is on call is read by the run, not by Firefight paging"
    assert_nil @workspace.paging_blocked_reason(@pagerduty)

    @workspace.ability_grants.where(principal: SystemAgent.paging, action: @pagerduty.tools.find_by!(name: "manage_incidents").ability_action).destroy_all
    tool = @pagerduty.tools.find_by!(name: "manage_incidents")
    tool.update!(enabled: false)
    tool.update!(enabled: true)

    assert_equal "Firefight paging no longer holds pagerduty.manage_incidents, so it cannot page through PagerDuty or keep its pages in step.",
                 @workspace.reload.paging_blocked_reason(@pagerduty)
  end

  test "the on-call page lists each on-call tool, why it cannot page, and where changes made there come back from" do
    @workspace.ability_grants.where(principal: SystemAgent.paging).destroy_all
    pagerduty_source!(@workspace, name: "PagerDuty prod")
    connect_opsgenie!(@workspace)

    get halon_on_call_url, headers: inertia_headers

    tools = inertia_props["pagingTools"]
    pagerduty = tools.find { |tool| tool["name"] == "PagerDuty" }
    assert_match "no longer holds", pagerduty["blockedReason"]
    assert_nil pagerduty["grantBlockedReason"]
    assert_equal "PagerDuty prod", pagerduty["returnSource"]
    opsgenie = tools.find { |tool| tool["name"] == "Opsgenie" }
    assert_nil opsgenie["returnSource"]
    assert_match "April 5, 2027", opsgenie["retiring"]
    assert_match "already holds every tool", opsgenie["grantBlockedReason"]
  end

  test "granting again gives Firefight paging its tools back and says so, and is refused with why when it would not help" do
    @workspace.ability_grants.where(principal: SystemAgent.paging).destroy_all

    post halon_paging_grant_url(@pagerduty.id)

    assert_redirected_to halon_on_call_path
    assert_equal "Firefight paging can page through PagerDuty again.", flash[:notice]
    assert_nil @workspace.reload.paging_blocked_reason(@pagerduty)

    @pagerduty.tools.find_by!(name: "browse_services").update!(enabled: false)
    post halon_paging_grant_url(@pagerduty.id)
    assert_equal "PagerDuty's browse_services is switched off under Integrations.", flash[:alert]
  end

  test "only someone who decides who may do what grants it" do
    @workspace.ability_grants.where(principal: SystemAgent.paging).destroy_all
    sign_in(users(:bob), @workspace)

    post halon_paging_grant_url(@pagerduty.id)

    assert_match "no longer holds", @workspace.reload.paging_blocked_reason(@pagerduty)
  end
end
