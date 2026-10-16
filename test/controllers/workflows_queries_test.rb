require "test_helper"

# What the workflows page costs the database. Each published workflow shows its runs and how they went, so more
# workflows, and more runs of each, must not mean more queries.
class WorkflowsQueriesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    sign_in(users(:alice), @workspace)
  end

  test "the page costs the same for many published workflows with many runs as for a few" do
    published(2, runs: 2)
    get halon_workflows_path, headers: inertia_headers
    few = queries_sent(cached: true) { get halon_workflows_path, headers: inertia_headers }
    published(8, runs: 6)
    many = queries_sent(cached: true) { get halon_workflows_path, headers: inertia_headers }

    assert_response :success
    assert_same_queries few, many
  end

  private

  def published(count, runs:)
    count.times do
      workflow = Workflow.create!(workspace: @workspace, name: "Look around #{SecureRandom.hex(3)}", created_by: @alice)
      workflow.open_draft!(by: @alice).update!(steps: [ { "id" => "look", "name" => "look", "kind" => "call_tool",
                                                          "config" => { "tool" => FirefightTools::SEARCH_INCIDENTS, "arguments" => {} } } ],
                                               trigger: { "kind" => "manual" })
      WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
      runs.times { WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }
    end
  end
end
