require "test_helper"

class Api::V1::WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    _, @token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Personal")
    @workflow = Workflow.create!(workspace: @workspace, name: "Restart web", created_by: @admin)
  end

  def change(workflow_id, given, token: @token) = patch(api_v1_workflow_url(workflow_id), params: given.to_json, headers: api_headers(token: token))

  test "changes a workflow's settings, by id or slug, and answers with all of them" do
    change(@workflow.id, { runs_per_hour: 250, cost_cap_cents: 300, freeze_behaviour: Workflow::FREEZE_WAIT, all_clear: true, subject_key: " {{inputs.service}} " })

    assert_response :success
    shown = json_response["workflow"]
    assert_equal [ @workflow.id, "restart_web", 250, 300, Workflow::FREEZE_WAIT, true, "{{inputs.service}}" ],
                 shown.values_at("id", "slug", "runs_per_hour", "cost_cap_cents", "freeze_behaviour", "all_clear", "subject_key")
    assert_equal [ 250, 300 ], @workflow.reload.values_at(:runs_per_hour, :cost_cap_cents)

    change("restart_web", { cost_cap_cents: nil, name: "Restart the web service", description: "Restarts web when it stops answering" })
    assert_response :success
    assert_nil @workflow.reload.cost_cap_cents
    assert_equal [ "Restart the web service", "Restarts web when it stops answering." ], @workflow.values_at(:name, :description)
  end

  test "only what is sent changes" do
    @workflow.update!(cost_cap_cents: 500, all_clear: true)

    change(@workflow.id, { runs_per_hour: 40 })

    assert_equal [ 40, 500, true ], @workflow.reload.values_at(:runs_per_hour, :cost_cap_cents, :all_clear)
  end

  test "a setting the page would refuse is refused with why, and nothing changes" do
    change(@workflow.id, { runs_per_hour: 0, cost_cap_cents: 900 })

    assert_response :unprocessable_entity
    assert_equal "runs_per_hour", json_response.dig("error", "errors", 0, "field")
    assert_equal [ 100, nil ], @workflow.reload.values_at(:runs_per_hour, :cost_cap_cents)
  end

  test "an owning team is a team on this workspace's catalog, and null takes it away" do
    team = catalog_entries(:platform_team)
    change(@workflow.id, { owner_team_id: team.id })
    assert_equal team, @workflow.reload.owner_team

    change(@workflow.id, { owner_team_id: nil })
    assert_nil @workflow.reload.owner_team
  end

  test "changing settings needs workflows update, which a member does not hold" do
    _, member_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @member, on_behalf_of: @member, name: "Bob's")

    change(@workflow.id, { runs_per_hour: 5 }, token: member_token)

    assert_response :forbidden
    assert_equal 100, @workflow.reload.runs_per_hour
  end
end
