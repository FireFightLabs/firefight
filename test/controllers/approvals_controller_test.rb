require "test_helper"

class ApprovalsControllerTest < ActionDispatch::IntegrationTest
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @approval = Ability::Approval.create!(
      workspace: @workspace, principal: api_keys(:full_access_key),
      principal_label: api_keys(:full_access_key).principal_label,
      action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
      required_role: WorkspaceMembership.roles[:admin]
    )
  end

  test "the approvals page lists pending and resolved approvals" do
    resolved = Ability::Approval.create!(
      workspace: @workspace, principal: api_keys(:full_access_key),
      principal_label: api_keys(:full_access_key).principal_label,
      action_key: "catalog.create", request_digest: Ability::Approval.digest("catalog.create", {}, {}),
      required_role: WorkspaceMembership.roles[:admin],
      status: Ability::Approval::STATUS_DENIED, resolved_at: Time.current
    )

    get gateway_approvals_url, headers: inertia_headers

    assert_response :success
    assert_equal [ @approval.id ], inertia_props["pendingApprovals"].map { |a| a["id"] }
    assert_equal [ resolved.id ], inertia_props["resolvedApprovals"].map { |a| a["id"] }
  end

  test "a command typed in Slack is shown on the approvals page as Slack shows it, and the record keeps it as sent" do
    bob = workspace_memberships(:bob_workspace_one)
    written = "<@#{bob.platform_user_id}> checkout is :fire: &amp; slow"
    params = { "command" => "/ff", "subcommand" => "investigate", "text" => "investigate #{written}" }
    command = Ability::Approval.create!(
      workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Alice",
      action_key: "investigations.create", params: params, source: AbilityGateway::SOURCE_SLACK,
      request_digest: Ability::Approval.digest("investigations.create", params, {}), required_role: WorkspaceMembership.roles[:admin]
    )

    get gateway_approvals_url, headers: inertia_headers

    shown = inertia_props["pendingApprovals"].find { |approval| approval["id"] == command.id }
    assert_equal "investigate @#{bob.display_name} checkout is 🔥 & slow", shown.dig("params", "text")
    assert_equal "/ff", shown.dig("params", "command")
    assert_equal "investigate #{written}", command.reload.params["text"]
  end

  test "the activity page renders the ledger" do
    AbilityGateway.authorize!(principal: api_keys(:full_access_key), action_key: "catalog.create",
                              workspace: @workspace) { :ok }

    get gateway_activity_url, headers: inertia_headers

    assert_response :success
    assert_equal [ "catalog.create" ], inertia_props["invocations"].map { |i| i["actionKey"] }
  end

  test "approve resolves the approval and redirects" do
    post approve_approval_url(@approval)

    assert_redirected_to gateway_approvals_path
    assert @approval.reload.approved?
    assert_equal "You approved Full Access Key's request. They can run it now.", flash[:notice]
  end

  test "approving a call Firefight parked to replay says it runs now" do
    kinds = [ ApprovalResumption::KIND_COMMAND, ApprovalResumption::KIND_INTERACTION, ApprovalResumption::KIND_WEB, ApprovalResumption::KIND_ISSUE_SYNC,
              ApprovalResumption::KIND_PAGING ]
    kinds.each do |kind|
      approval = held(workspace_memberships(:bob_workspace_one), "catalog.delete", resume_payload: { kind: kind })

      post approve_approval_url(approval)

      assert_equal "You approved Bob Jones's request. It runs now.", flash[:notice], kind
    end
  end

  test "approving a workflow's Approval step says its run goes on" do
    approval = held(workflow_agent, Ability::Action::WORKFLOW_APPROVAL)
    ApprovalResumption.park_workflow_step!(approval, "engine-step", "check")

    post approve_approval_url(approval)

    assert_equal "You approved Weekday probe check workflow's request. Its run goes on.", flash[:notice]
  end

  test "approving a call a workflow's step made says its run goes on and makes the call" do
    approval = held(workflow_agent, "catalog.delete")
    ApprovalResumption.park_workflow_step!(approval, "engine-step", "remove")

    post approve_approval_url(approval)

    assert_equal "You approved Weekday probe check workflow's request. Its run goes on and makes the call.", flash[:notice]
  end

  test "approving publishing a workflow says it is published, and says when granting what it needs can wait as well" do
    calm = drafted_workflow("Calm down", { "id" => "wait", "name" => "wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } })
    look = drafted_workflow("Look around", { "id" => "look", "name" => "look", "kind" => "call_tool",
                                             "config" => { "tool" => FirefightTools::SEARCH_INCIDENTS, "arguments" => {} } })
    granting = held(SystemAgent.investigator, Workflow::GRANT_KEY)
    ApprovalResumption.park_workflow_publish!(granting, look, revision: look.draft.revision, source: AbilityGateway::SOURCE_MCP,
                                                              stage: WorkflowPublishService::STAGE_GRANT)
    said = [ calm, look ].map do |workflow|
      approval = held(SystemAgent.investigator, Workflow::PUBLISH_KEY)
      ApprovalResumption.park_workflow_publish!(approval, workflow, revision: workflow.draft.revision, source: AbilityGateway::SOURCE_MCP,
                                                                    stage: WorkflowPublishService::STAGE_PUBLISH)
      post approve_approval_url(approval)
      flash[:notice]
    end
    post approve_approval_url(granting)
    said << flash[:notice]

    halon = SystemAgent.investigator.actor_display_name
    assert_equal [ "You approved #{halon}'s request. Calm down is published now.",
                   "You approved #{halon}'s request. Look around is published now, unless granting what it needs waits on an approval too.",
                   "You approved #{halon}'s request. Look around is published now." ], said
  end

  test "approving a step of a fix says whoever applied the fix can run it" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: workspace_memberships(:bob_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    approval = held(workspace_memberships(:bob_workspace_one), "cloudflare.execute")
    ApprovalResumption.park_fix_step!(approval, plan.steps.first)

    post approve_approval_url(approval)

    assert_equal "You approved Bob Jones's request. Bob Jones can run it now.", flash[:notice]
  end

  test "a member without an approvals grant is refused by the gateway" do
    sign_in(users(:bob), @workspace)

    post deny_approval_url(@approval)

    assert_redirected_to dashboard_path
    assert_match "don't have permission to change approvals", flash[:alert]
    assert @approval.reload.pending?
  end

  test "deny without the required role redirects with the refusal" do
    sign_in(users(:bob), @workspace)
    @workspace.ability_grants.create!(
      principal: workspace_memberships(:bob_workspace_one),
      action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE))
    )

    post deny_approval_url(@approval)

    assert_redirected_to gateway_approvals_path
    assert_equal "requires the admin role", flash[:alert]
    assert @approval.reload.pending?
  end

  test "a member a workflow's Approval step names decides that request on the approvals page without approvals access" do
    bob = workspace_memberships(:bob_workspace_one)
    asked = { "question" => "Release checkout?" }
    named = Ability::Approval.create!(
      workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Release workflow",
      action_key: Ability::Action::WORKFLOW_APPROVAL, request_digest: Ability::Approval.digest(Ability::Action::WORKFLOW_APPROVAL, asked, {}),
      params: asked, required_role: WorkspaceMembership.roles[:admin], approver_ids: Ability::Principal.references([ bob.id ])
    )
    sign_in(users(:bob), @workspace)

    get gateway_approvals_url, headers: inertia_headers
    reasons = inertia_props["pendingApprovals"].to_h { |row| [ row["id"], row["decideDeniedReason"] ] }
    assert_nil reasons[named.id]
    assert_equal "You don't have permission to decide this request. Ask a workspace admin to grant you approvals access under Gateway, Permissions.", reasons[@approval.id]

    post approve_approval_url(@approval)
    assert @approval.reload.pending?
    assert_match "permission", flash[:alert]

    post approve_approval_url(named)
    assert_redirected_to gateway_approvals_path
    assert_equal "You approved #{workspace_memberships(:alice_workspace_one).actor_display_name}'s request. They can run it now.", flash[:notice]
    assert named.reload.approved?
  end

  private

  def held(principal, action_key, **attributes)
    Ability::Approval.create!(workspace: @workspace, principal: principal, principal_label: principal.principal_label, action_key: action_key,
                              request_digest: Ability::Approval.digest(action_key, {}, {}), required_role: WorkspaceMembership.roles[:admin], **attributes)
  end

  def workflow_agent = Workflow.create!(workspace: @workspace, name: "Weekday probe check").ensure_agent!

  def drafted_workflow(name, step)
    workflow = Workflow.create!(workspace: @workspace, name: name)
    workflow.open_draft!(by: workspace_memberships(:alice_workspace_one)).update!(steps: [ step ])
    workflow
  end

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
