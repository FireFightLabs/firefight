require "test_helper"

class Investigation::FixRunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @investigation.steps.create!(position: 1, tool_name: "commit_lookup", label: "Commit lookup", action_key: "github.commit_lookup",
                                 status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    @cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                  settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    @cloudflare.integration_environments.create!
    @execute = @cloudflare.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    @investigation.record_hypothesis!(assertion: "A WAF rule blocks checkout", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    finding = @investigation.conclude!(
      summary: "A WAF rule blocked checkout", hypothesis_assertion: "A WAF rule blocks checkout",
      evidence: [ { claim: "The rule was added at 14:02", steps: [ 1 ] } ],
      fix: { "summary" => "Remove the rule", "steps" => [
        { "kind" => "action", "description" => "Delete the rule", "tool" => "cloudflare_execute", "arguments" => { "code" => "delete" } },
        { "kind" => "manual", "description" => "Tell security", "depends_on" => [ 1 ] },
        { "kind" => "action", "description" => "Purge the cache", "tool" => "cloudflare_execute", "arguments" => { "code" => "purge" }, "depends_on" => [ 2 ] },
        { "kind" => "action", "description" => "Log it", "tool" => "cloudflare_execute", "arguments" => { "code" => "log" } }
      ] }
    )
    @investigation.update!(thread_id: "1.1")
    @plan = finding.remediation_plan
    @adapter = stub(post_fix_progress: { message_id: "1.2", channel_id: "C1" }, update_fix_progress: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
  end

  test "applying runs every ready tool step as the person, and a step waiting on a person waits" do
    Integrations::McpExecutor.expects(:call).with { |tool:, arguments:, **| tool == @execute && arguments == { "code" => "delete" } }
                             .returns("content" => [ { "type" => "text", "text" => "Rule deleted" } ])
    Integrations::McpExecutor.expects(:call).with { |arguments:, **| arguments == { "code" => "log" } }.returns("content" => [])
    @investigation.update!(answer_message_id: "1.5")
    @adapter.expects(:update_investigation_answer).with { |message_id:, finding:, **| message_id == "1.5" && finding == @plan.finding }.once

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { assert_nil Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    delete, tell, purge, log = @plan.steps.reload.to_a
    assert_equal [ "done", "Rule deleted" ], [ delete.status, delete.result ]
    assert_equal Ability::Invocation::DECISION_ALLOW, delete.invocation.decision
    assert_equal [ @alice, AbilityGateway::SOURCE_WEB ], [ delete.invocation.principal, delete.invocation.source ]
    assert_equal [ "proposed", "proposed", "done" ], [ tell.status, purge.status, log.status ]
    assert_equal [ Investigation::RemediationPlan::STATUS_APPLYING, @alice ], [ @plan.reload.status, @plan.approved_by ]
    assert_equal [ "C1", "1.2" ], [ @plan.progress_channel_id, @plan.progress_message_id ]
  end

  test "a step that named a capability runs as the provider call it was resolved to, and a failed answer fails the step" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "cloudflare", account: "Acme", kind: ResourceMap::KIND_WORKER, external_id: "api",
                                  name: "api", url: "https://dash.cloudflare.com/acc1/workers-and-pages", integration_environment: @cloudflare.integration_environments.first,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
    @plan.destroy!
    finding = @investigation.reload.finding
    Investigation::RemediationPlan.propose!(finding, { "summary" => "Roll api back", "steps" => [
      { "kind" => "action", "description" => "Put api back on version 8", "tool" => "rollback", "arguments" => { "resource" => "api", "to" => "ver-8" } }
    ] })
    plan = finding.reload.remediation_plan
    Integrations::McpExecutor.expects(:call).with { |tool:, arguments:, **| tool == @execute && arguments["code"].include?("/accounts/acc1/workers/scripts/api/deployments") }
                             .returns("content" => [ { "type" => "text", "text" => "Error: version not found" } ], "isError" => true)

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    step = plan.steps.reload.sole
    assert_equal [ "rollback", "cloudflare.execute", "failed" ], [ step.tool_name, step.action_key, step.status ]
  end

  test "marking a person's step done lets what waits on it run, and the fix settles once every step ended" do
    Integrations::McpExecutor.stubs(:call).returns("content" => [])
    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_SLACK) }

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { assert_nil Investigation::FixRunner.mark_done!(@plan.steps.second, by: @bob) }

    assert_equal %w[done done done done], @plan.steps.reload.map(&:status)
    assert_equal @bob, @plan.steps.second.done_by
    assert_equal Investigation::RemediationPlan::STATUS_APPLIED, @plan.reload.status
    assert_match "already done", Investigation::FixRunner.mark_done!(@plan.steps.second, by: @bob)
    assert_match "runs step 1 itself", Investigation::FixRunner.mark_done!(@plan.steps.first, by: @bob)
  end

  test "a step that fails stops what waits on it, the rest stand, and the fix is partly applied" do
    Integrations::McpExecutor.stubs(:call).with { |arguments:, **| arguments == { "code" => "delete" } }.raises(Integrations::Error, "Cloudflare answered 403")
    Integrations::McpExecutor.stubs(:call).with { |arguments:, **| arguments == { "code" => "log" } }.returns("content" => [ { "type" => "text", "text" => "No such rule" } ], "isError" => true)

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    assert_equal [ [ "failed", "Cloudflare answered 403" ], [ "skipped", nil ], [ "skipped", nil ], [ "failed", "No such rule" ] ],
                 @plan.steps.reload.map { |step| [ step.status, step.result ] }
    assert_equal Investigation::RemediationPlan::STATUS_PARTLY_APPLIED, @plan.reload.status
    assert_equal Ability::Invocation::OUTCOME_ERROR, @plan.steps.first.invocation.outcome
  end

  test "a step an approval rule holds waits, runs once approved, and a declined one stops what waits on it" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    Integrations::McpExecutor.stubs(:call).returns("content" => [])
    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    delete, = @plan.steps.reload.to_a
    assert_equal Investigation::RemediationStep::STATUS_WAITING_APPROVAL, delete.status
    perform_enqueued_jobs(only: [ AbilityApprovalResumptionJob, InvestigationFixJob ], at: Time.current) { delete.approval.approve!(by: @alice) }
    assert_equal "done", delete.reload.status

    log = @plan.steps.reload.fourth
    perform_enqueued_jobs(only: [ AbilityApprovalResumptionJob, InvestigationFixJob ], at: Time.current) { log.approval.deny!(by: @alice) }
    assert_equal [ "declined", "Alice Smith declined it." ], [ log.reload.status, log.result ]
  end

  test "nobody applies a fix twice, someone without access to a tool is told which step before anything runs, and a fix with nothing to run is never applied" do
    assert_match "Step 1 runs cloudflare_execute, which you have no access to", Investigation::FixRunner.apply!(@plan, by: @bob, from: AbilityGateway::SOURCE_WEB)
    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status

    Integrations::McpExecutor.stubs(:call).returns("content" => [])
    assert_nil Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB)
    assert_match "Alice Smith already applied this fix", Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB)

    @execute.update!(enabled: false)
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PROPOSED)
    assert_match "no longer switched on", @plan.reload.apply_blocked_reason
  end

  test "a person's step cannot be marked done before what it waits on, so it never lets a step run past a failure" do
    assert_equal "Step 2 waits on step 1, which is not done yet.", Investigation::FixRunner.mark_done!(@plan.steps.second, by: @bob)

    Integrations::McpExecutor.stubs(:call).raises(Integrations::Error, "Cloudflare answered 500")
    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    assert_equal %w[failed skipped skipped failed], @plan.steps.reload.map(&:status)
  end

  test "a credential a tool hands back is redacted before it is kept or shown" do
    Integrations::McpExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "New token ghp_#{'a' * 36} created" } ])

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    assert_equal "New token [REDACTED:github_token] created", @plan.steps.first.reload.result
  end

  test "a step never stays running: an error before the call fails it, a lost worker is given up on, and a gone applier is said" do
    Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB)
    AbilityGateway.stubs(:authorize!).raises(Timeout::Error)
    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current)
    assert_equal [ "failed", Investigation::FixRunner::COULD_NOT_FINISH ], [ @plan.steps.first.reload.status, @plan.steps.first.result ]
    AbilityGateway.unstub(:authorize!)

    log = @plan.steps.fourth
    log.update_columns(status: Investigation::RemediationStep::STATUS_RUNNING, started_at: 20.minutes.ago)
    Investigation::FixRunner.new(@plan).advance!
    assert_equal [ "failed", Investigation::FixRunner::LOST_TRACK ], [ log.reload.status, log.result ]

    @plan.update_columns(approved_by_id: nil, status: Investigation::RemediationPlan::STATUS_APPLYING)
    log.update_columns(status: Investigation::RemediationStep::STATUS_PROPOSED, result: nil)
    Investigation::FixRunner.new(@plan.reload).advance!
    assert_equal Investigation::FixRunner::APPLIER_GONE, log.reload.result
  end

  test "a tool switched off after the fix was applied fails its step with why" do
    Integrations::McpExecutor.expects(:call).never
    Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB)
    @execute.update!(enabled: false)

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current)

    assert_equal [ "failed", "cloudflare_execute is no longer switched on." ], [ @plan.steps.first.reload.status, @plan.steps.first.result ]
  end
end
