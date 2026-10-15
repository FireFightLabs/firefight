require "test_helper"

# What a run's fix costs the database when its page opens. Each step shows who approved it and what would write a code
# change, so a fix of many steps must not cost more than a fix of a few.
class InvestigationFixQueriesTest < ActionDispatch::IntegrationTest
  include FixPlanTestHelper
  include CodeQuestionTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:available_for?).returns(true)
    sign_in(users(:alice), @workspace)
    @plan = build_fix_plan(@workspace)
    @investigation = @plan.finding.investigation
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(credentials: { token: "x" }.to_json)
    code_fix = IntegrationProvider.find("github").code_fix_tool
    github.tools.create!(name: code_fix, description: "Writes a change", params_schema: {}, enabled: true, read_only: false)
  end

  test "a fix of many approved and code steps costs the same as a fix of a few" do
    steps(2)
    page
    few = queries_sent { page }
    steps(10)
    many = queries_sent { page }

    assert_same_queries few, many
  end

  private

  def page
    get incident_path(@investigation.incident, Investigation::QUERY_PARAM => @investigation.id), headers: inertia_headers
    assert_response :success
  end

  # A coding agent that asked a question and then paused at its spending limit.
  def paused_work
    member = workspace_memberships(:alice_workspace_one)
    request = CodeAgent::Request.new(principal: member, source: AbilityGateway::SOURCE_CONVERSATION, place: @investigation, tool_call_id: SecureRandom.hex(4))
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    pause = CodeAgentSession::Pause.create!(session: session, workspace: @workspace, arguments: { "repo" => "acme/api" },
                                            repository: "acme/api", base: "main", copy_ref: "c" * 40, budget_micros: 2_000_000,
                                            resumable_until: 15.minutes.from_now, status: CodeAgentSession::Pause::STATUS_OFFERED)
    Chat::CodeFixProgress.start.tap do |work|
      work.asked!(ask_question!(session, "Tag or commit?").to_h)
      work.paused!(pause.to_h)
    end
  end

  def steps(count)
    count.times do
      position = @plan.steps.maximum(:position) + 1
      approval = Ability::Approval.create!(workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Alice",
                                           action_key: "cloudflare.execute", request_digest: Ability::Approval.digest("cloudflare.execute", { "n" => position }, {}),
                                           required_role: WorkspaceMembership.roles[:admin], status: Ability::Approval::STATUS_APPROVED,
                                           approver: workspace_memberships(:alice_workspace_one), resolved_at: Time.current, run_expires_at: 1.hour.from_now)
      @plan.steps.create!(position: position, kind: Investigation::RemediationStep::KIND_ACTION, description: "Delete rule #{position}",
                          action_key: "cloudflare.execute", tool_name: "cloudflare_execute", arguments: { "code" => "delete" },
                          status: Investigation::RemediationStep::STATUS_APPROVED, approval: approval)
      @plan.steps.create!(position: position + 1, kind: Investigation::RemediationStep::KIND_PULL_REQUEST, description: "Drop rule #{position}",
                          repository: "acme/infra-#{position}", status: Investigation::RemediationStep::STATUS_RUNNING, progress: paused_work.to_json)
    end
  end
end
