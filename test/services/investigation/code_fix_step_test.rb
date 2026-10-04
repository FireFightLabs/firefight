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

  test "a coding agent the workspace chose writes the change instead of the code host, and a person does it while the agent is off" do
    devin = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "devin", name: "Devin", slug: "devin")
    devin.integration_environments.create!
    devin_fix = devin.tools.create!(name: "fix_code", description: "Hands a change to Devin", params_schema: {}, enabled: true, read_only: false)
    code = @plan.steps.third
    assert_equal @fix_code, code.tool_to_run, "Firefight's own agent writes it until someone chooses another"

    @workspace.update!(code_fix_agent: "devin")
    assert_equal devin_fix, code.reload.tool_to_run
    assert_equal "Firefight hands step 3's change to Devin once the fix is applied, and Devin opens the pull request.", code.mark_done_blocked_reason

    devin_fix.update!(enabled: false)
    assert_not code.reload.runs_itself?, "the chosen agent is off, so the change is a person's, never quietly Firefight's own"
    assert_equal "Devin's fix_code tool is switched off, so code steps wait for a person. Switch it on under Integrations.", @workspace.code_fix_agent_blocked_reason
  end

  test "what the coding agent says while it works shows on the step, and its answer replaces it" do
    devin = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "devin", name: "Devin", slug: "devin")
    Integrations::Packs::Devin.store_credentials!(devin.integration_environments.create!,
                                                  Integrations::Packs::Devin::API_KEY => "cog_key", Integrations::Packs::Devin::ORGANIZATION => "org-abc")
    devin.tools.create!(name: "fix_code", description: "Hands a change to Devin", params_schema: {}, enabled: true, read_only: false)
    @workspace.update!(code_fix_agent: "devin")
    Integrations::McpExecutor.stubs(:call).returns("content" => [])
    Integrations::Packs::Devin.any_instance.stubs(:pause)
    Integrations::DevinApi.any_instance.expects(:create_session).with { |body| body["prompt"].include?("Why: A WAF rule blocked checkout") }
                          .returns("session_id" => "devin-1", "url" => "https://app.devin.ai/sessions/devin-1")
    seen = nil
    Integrations::DevinApi.any_instance.stubs(:session).with { seen ||= @plan.steps.third.reload.result }
                          .returns("status" => "exit", "acus_consumed" => 1, "pull_requests" => [ { "pr_url" => "https://github.com/acme/infra/pull/9" } ])
    Integrations::DevinApi.any_instance.stubs(:messages).returns("items" => [])

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    code = @plan.steps.third.reload
    assert_equal "Devin is writing the change in session devin-1. Follow it at https://app.devin.ai/sessions/devin-1.", seen
    assert_equal "done", code.status
    assert code.result.start_with?("Devin opened https://github.com/acme/infra/pull/9 for acme/infra.")
    assert_equal "devin.fix_code", code.invocation.action_key
    assert_not code.progress!("Too late"), "a step that ended keeps how it ended"
  end
end
