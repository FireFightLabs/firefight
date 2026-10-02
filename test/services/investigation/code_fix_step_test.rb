require "test_helper"

class Investigation::CodeFixStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @alice = workspace_memberships(:alice_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    @github_row = @github.integration_environments.create!(base_config: { "installation_id" => "1" })
    @fix_code = @github.tools.create!(name: "fix_code", description: "Writes code", params_schema: {}, enabled: true, read_only: false)
    WorkspaceAdapter.stubs(:for).returns(stub(post_fix_progress: { message_id: "1.2", channel_id: "C1" }, update_fix_progress: { success: true },
                                              update_investigation_answer: { success: true }))
  end

  test "a code change runs itself once the workspace can open its pull request, and is a person's step otherwise" do
    code = @plan.steps.third
    assert code.runs_itself?
    assert_equal "Firefight opens step 3's pull request itself once the fix is applied.", code.mark_done_blocked_reason

    @fix_code.update!(enabled: false)
    assert_not code.reload.runs_itself?
    assert_nil code.mark_done_blocked_reason
  end

  test "with two code hosts, the step uses the one whose sweep put its repository on the map" do
    other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub two", slug: "github_two")
    other_row = other.integration_environments.create!(base_config: { "installation_id" => "2" })
    other_tool = other.tools.create!(name: "fix_code", description: "Writes code", params_schema: {}, enabled: true, read_only: false)
    code = @plan.steps.third
    assert_nil code.tool_to_run, "two connections and nothing says which sees the repository"

    ResourceMap.record!(other_row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/infra", name: "acme/infra")
    ]))
    assert_equal other_tool, code.tool_to_run
    assert_not_equal @github_row, other_row
  end

  test "applying the fix asks the coding tool for the change, as the person, with the finding as its brief" do
    Integrations::McpExecutor.stubs(:call).returns("content" => [])
    Integrations::NativeExecutor.expects(:call).with do |tool:, arguments:, **|
      tool == @fix_code && arguments["repo"] == "acme/infra" && arguments["title"] == "Drop the rule from dns.tf" &&
        arguments["brief"].include?("Why: A WAF rule blocked checkout") && arguments["brief"].include?("- The rule was added at 14:02")
    end.returns("content" => [ { "type" => "text", "text" => "Opened https://github.com/acme/infra/pull/9 on acme/infra against main." } ])

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    code = @plan.steps.third.reload
    assert_equal [ "done", "Opened https://github.com/acme/infra/pull/9 on acme/infra against main." ], [ code.status, code.result ]
    assert_equal "github.fix_code", code.invocation.action_key
    assert_equal "acme/infra", code.arguments["repo"], "the arguments are fixed when it starts, so an approval still matches on resume"
  end
end
