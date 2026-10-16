require "test_helper"

# Where the workspace has workflows, a runbook written over the API keeps its steps as the checklist and what it runs in
# the workflow it links, which waits as a draft, since the API publishes no workflow.
class Api::V1::RunbookWorkflowsApiTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    _, @token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Personal")
  end

  test "a runbook with a tool step is written as a checklist and a draft workflow it links, shown with its inputs and watch" do
    post api_v1_runbooks_url, headers: api_headers(token: @token), params: {
      name: "Release Firefight",
      inputs: [ { key: "bump", question: "Which version bump?", default: "patch" } ],
      steps: [ { title: "Look for past releases", tool: "search_incidents", arguments: { query: "release {{bump}}" } } ]
    }, as: :json
    assert_response :created

    body = json_response["runbook"]
    assert_equal [ { "position" => 1, "title" => "Look for past releases", "instruction" => nil, "tool" => nil, "arguments" => {} } ], body["steps"]
    assert_equal [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ], body["inputs"]
    assert_equal Workflow::STATE_DRAFT, body.dig("workflow", "state")
    assert_equal "Release Firefight waits as a draft. Publish it from its page.", body.dig("workflow", "said")
    assert_equal [ { "title" => "look_for_past_releases", "tool" => "search_incidents", "arguments" => { "query" => "release {{bump}}" } } ], body.dig("workflow", "steps")

    workflow = @workspace.runbooks.find_by!(slug: "release_firefight").workflow
    assert_not workflow.live?
    assert_equal @admin, workflow.draft.author
  end

  test "a key that may not make workflows cannot write what a runbook runs, and nothing is saved" do
    _, token = create_service_key(workspace: @workspace, created_by: @admin, name: "Writer",
                                  permissions: { Ability::Action::RESOURCE_RUNBOOKS => [ Ability::Action::ACTION_READ, Ability::Action::ACTION_CREATE ] })

    post api_v1_runbooks_url, headers: api_headers(token: token), params: {
      name: "Release Firefight", steps: [ { title: "Look", tool: "search_incidents", arguments: {} } ]
    }, as: :json

    assert_response :forbidden
    assert_nil @workspace.runbooks.find_by(slug: "release_firefight")
    assert_nil @workspace.workflows.find_by(slug: "release_firefight")
  end
end
