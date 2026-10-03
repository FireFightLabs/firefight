require "test_helper"

class Investigation::RemediationPlanTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @investigation.steps.create!(position: 1, tool_name: "commit_lookup", label: "Commit lookup abc123", action_key: "github.commit_lookup",
                                 status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                 settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    cloudflare.integration_environments.create!
    cloudflare.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    cloudflare.tools.create!(name: "search", description: "Search the spec", params_schema: {}, enabled: true, read_only: true)
    cloudflare.tools.create!(name: "purge", description: "Purge the cache", params_schema: {}, enabled: false, read_only: false)
    @investigation.record_hypothesis!(assertion: "The WAF rule added at 14:02 blocks checkout", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
  end

  test "a cause comes with its fix, each step saying how it gets done, how to undo it, and what it waits on" do
    finding = conclude(fix: {
      summary: "Remove the WAF rule and keep it in code", verify: "Checkout 403s back to zero",
      steps: [
        { kind: "action", description: "Delete the rule", tool: "cloudflare_execute", arguments: { code: "async () => 1" }, undo: "Add the rule back" },
        { kind: "pull_request", description: "Drop the rule from dns.tf", repository: "acme/infra", depends_on: [ 1 ] },
        { kind: "manual", description: "Tell the security team", missing: "No chat tool is connected" }
      ]
    })

    plan = finding.remediation_plan
    assert_equal [ "Remove the WAF rule and keep it in code", "Checkout 403s back to zero" ], [ plan.summary, plan.verify ]
    action, pull_request, manual = plan.steps.to_a
    assert_equal [ "cloudflare.execute", { "code" => "async () => 1" }, "Add the rule back" ], [ action.action_key, action.arguments, action.undo ]
    assert_equal [ "acme/infra", [ 1 ] ], [ pull_request.repository, pull_request.depends_on ]
    assert_equal "No chat tool is connected", manual.missing
  end

  test "a step can name a capability, and it is kept as the provider call it will make, a read never being a fix" do
    environment_row = @workspace.integrations.find_by!(slug: "cloudflare").integration_environments.first
    ResourceMap::Resource.create!(workspace: @workspace, provider: "cloudflare", account: "Acme", kind: ResourceMap::KIND_WORKER, external_id: "api",
                                  name: "api", url: "https://dash.cloudflare.com/acc1/workers-and-pages", integration_environment: environment_row,
                                  first_seen_at: Time.current, last_seen_at: Time.current)

    checked = Investigation::RemediationPlan.check!(@workspace, { "summary" => "Roll api back", "steps" => [
      { "kind" => "action", "description" => "Put api back on the last good version", "tool" => "rollback", "arguments" => { "resource" => "api", "to" => "ver-8" } }
    ] })

    step = checked.steps.sole
    assert_equal [ "rollback", "cloudflare.execute" ], [ step.tool_name, step.action_key ]
    assert_includes step.arguments["code"], '"path":"/accounts/acc1/workers/scripts/api/deployments"'
    error = assert_raises(Investigation::RemediationPlan::Refused) do
      Investigation::RemediationPlan.check!(@workspace, { "summary" => "Look", "steps" => [ { "kind" => "action", "description" => "Read logs", "tool" => "search_logs", "arguments" => { "resource" => "api" } } ] })
    end
    assert_match "only reads", error.message
  end

  test "naming a cause without a fix is sent back, and nothing is recorded" do
    error = assert_raises(Investigation::RemediationPlan::Refused) { conclude(fix: nil) }

    assert_match "needs a fix", error.message
    assert_nil @investigation.reload.finding
  end

  test "a step the workspace cannot run is sent back with what to do instead" do
    refused = ->(step) { assert_raises(Investigation::RemediationPlan::Refused) { conclude(fix: { summary: "Fix it", steps: [ step ] }) }.message }

    assert_match "has not switched on. Make it a manual step", refused.({ kind: "action", description: "Purge", tool: "cloudflare_purge" })
    assert_match "only reads", refused.({ kind: "action", description: "Look", tool: "cloudflare_search" })
    assert_match "names no repository", refused.({ kind: "pull_request", description: "Change the code" })
    assert_match "not one of", refused.({ kind: "rollback", description: "Roll back" })
    assert_match "depends on step 2", refused.({ kind: "manual", description: "Wait", depends_on: [ 2 ] })
  end

  test "an answer with no cause needs no fix, and may still carry one" do
    assert_nil @investigation.conclude!(summary: "Nothing explains it yet").remediation_plan

    other = @workspace.investigations.create!(brief: { Investigation::Brief::KEY_SYMPTOM => "web is slow" }, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    finding = other.conclude!(summary: "Unclear, but restarting clears it", fix: { "summary" => "Restart", "steps" => [ { "kind" => "manual", "description" => "Restart web" } ] })
    assert_equal [ "Restart web" ], finding.remediation_plan.steps.map(&:description)
  end

  test "a fix arrives as the model sends it, keyed by text, and only this workspace's tools count" do
    other = workspaces(:slack_workspace_two).integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                                  settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    other.integration_environments.create!
    other.tools.create!(name: "purge", description: "Purge the cache", params_schema: {}, enabled: true, read_only: false)

    finding = conclude(fix: { "summary" => "Delete the rule", "steps" => [ { "kind" => "action", "description" => "Delete it", "tool" => "cloudflare_execute",
                                                                            "arguments" => { "code" => "async () => 1", "account_id" => "a" } } ] })
    assert_equal({ "code" => "async () => 1", "account_id" => "a" }, finding.remediation_plan.steps.sole.arguments)

    other_run = @workspace.investigations.create!(brief: { Investigation::Brief::KEY_SYMPTOM => "the cache is stale" }, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    error = assert_raises(Investigation::RemediationPlan::Refused) do
      other_run.conclude!(summary: "Purge", fix: { "summary" => "Purge", "steps" => [ { "kind" => "action", "description" => "Purge", "tool" => "cloudflare_purge" } ] })
    end
    assert_match "has not switched on", error.message
  end

  test "a fix that is not shaped as asked, or holds a secret, is sent back rather than breaking the run" do
    refused = ->(fix) { assert_raises(Investigation::RemediationPlan::Refused) { conclude(fix: fix) }.message }

    assert_match "must be an object", refused.("delete the rule")
    assert_match "steps as a list", refused.({ "summary" => "Fix", "steps" => "delete it" })
    assert_match "arguments as something other than an object", refused.({ "summary" => "Fix", "steps" => [ { "kind" => "action", "description" => "Delete", "tool" => "cloudflare_execute", "arguments" => "rm" } ] })
    assert_match "looks like a secret", refused.({ "summary" => "Fix", "steps" => [ { "kind" => "manual", "description" => "Connect with postgres://app:hunter2@db.internal/prod" } ] })
  end

  private

  def conclude(fix:)
    @investigation.conclude!(summary: "A WAF rule blocked checkout", hypothesis_assertion: "The WAF rule added at 14:02 blocks checkout",
                             evidence: [ { claim: "The rule was added at 14:02", steps: [ 1 ] } ], fix: fix)
  end
end
