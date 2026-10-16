require "test_helper"

class Investigation::PageCheckStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  JPEG = "\xFF\xD8\xFF\xE0fake-jpeg".b.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @investigation.steps.create!(position: 1, tool_name: "commit_lookup", label: "Commit lookup", action_key: "github.commit_lookup",
                                 status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                 settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    cloudflare.integration_environments.create!
    cloudflare.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    @investigation.record_hypothesis!(assertion: "A WAF rule blocks checkout", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    WorkspaceAdapter.stubs(:for).returns(stub(post_fix_progress: { message_id: "1.2", channel_id: "C1" }, post_fix_ended: { message_id: "1.3", channel_id: "C1" }, update_fix_progress: { success: true }))
    Integrations::McpExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "Rule deleted" } ])
  end

  test "a page check runs last, after the change, opens the page as whoever applied the fix and keeps what it saw under the step" do
    plan = concluded(page_check)
    check = plan.steps.find(&:page_check?)
    assert_equal [ [ 1 ], Ability::Action::BROWSER_READ ], [ check.depends_on, check.action_key ]
    handed = nil
    Integrations::Terminal.any_instance.expects(:browse).with { |spec| handed = spec }.returns(browsed(status: 200))

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { assert_nil Investigation::FixRunner.apply!(plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    assert_equal [ "https://shop.example.com/checkout", nil ], handed.values_at("url", "send_step")
    check.reload
    assert_equal [ Investigation::RemediationStep::STATUS_DONE, Investigation::FixRunner::PAGE_WORKS ], [ check.status, check.result ]
    assert_equal [ Ability::Action::BROWSER_READ, @alice ], [ check.invocation.action_key, check.invocation.principal ]
    assert_equal [ check.id ], @investigation.reload.chat.screenshots.pluck(:remediation_step_id)
    assert_equal Investigation::RemediationPlan::STATUS_APPLIED, plan.reload.status
  end

  test "a page that still fails fails the check, saying what went wrong" do
    plan = concluded(page_check)
    Integrations::Terminal.any_instance.stubs(:browse).returns(browsed(status: 500, console: [ { "type" => "error", "text" => "boom" } ]))

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }

    check = plan.steps.reload.find(&:page_check?)
    assert_equal Investigation::RemediationStep::STATUS_FAILED, check.status
    assert_equal "Desktop: the page answered 500.\nDesktop: 1 console error.", check.result
  end

  test "a fix of page checks alone is not one to apply, a page check is never marked done by hand, and one the browser cannot follow is refused" do
    plan = concluded(page_check.merge("depends_on" => []), change: false)
    assert_not plan.appliable?
    assert_match "runs step", plan.steps.sole.mark_done_blocked_reason

    refused = assert_raises(Investigation::RemediationPlan::Refused) { checked(page_check.merge("arguments" => { "url" => "ftp://shop.example.com" })) }
    assert_match "page check Halon's browser cannot follow", refused.message
    refused = assert_raises(Investigation::RemediationPlan::Refused) do
      checked(page_check.merge("arguments" => { "url" => "https://shop.example.com", "steps" => [ { "action" => "click", "text" => "Pay" } ], "send_step" => 1 }))
    end
    assert_match "only reads", refused.message
  end

  private

  def page_check
    { "kind" => Investigation::RemediationStep::KIND_PAGE_CHECK, "description" => "Confirm checkout works",
      "arguments" => { "url" => "https://shop.example.com/checkout", "viewports" => [ "desktop" ] } }
  end

  def concluded(check, change: true)
    action = { "kind" => "action", "description" => "Delete the rule", "tool" => "cloudflare_execute", "arguments" => { "code" => "delete" } }
    steps = (change ? [ action ] : []) + [ check ]
    @investigation.conclude!(summary: "A WAF rule blocked checkout", hypothesis_assertion: "A WAF rule blocks checkout",
                             evidence: [ { claim: "The rule was added at 14:02", steps: [ 1 ] } ],
                             fix: { "summary" => "Remove the rule", "steps" => steps }).remediation_plan
  end

  def checked(asked) = Investigation::RemediationStep.checked(@workspace, asked, position: 2, principal: @alice)

  def browsed(status:, console: [])
    Integrations::Terminal::Browsed.new(region: "EU", answer: { "viewports" => [
      { "name" => "desktop", "status" => status, "final_url" => "https://shop.example.com/checkout", "title" => "Checkout", "console" => console,
        "steps" => [], "screenshot" => Base64.strict_encode64(JPEG) }
    ] })
  end
end
