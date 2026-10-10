require "test_helper"

class Ability::OnCallApprovalTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @incident.incident_role_assignments.destroy_all
    @bob = workspace_memberships(:bob_workspace_one)
    @admin = @workspace.workspace_memberships.admins_and_owners.first
    IncidentEscalationWorkflow.stubs(:start!)
  end

  def approval(on_call:)
    requirement = PolicyRule::ApprovalOutcome.build(role: WorkspaceMembership.roles[:admin], on_call: on_call)[PolicyRule::ApprovalOutcome::REQUIRE_KEY]
    @workspace.ability_approvals.create!(
      principal_type: SystemAgent.name, principal_id: SystemAgent.investigator.id, principal_label: "Halon", action_key: "northflank.api_request",
      request_digest: "x", incident_id: @incident.id, **Ability::Approval.requirement_attributes(requirement)
    )
  end

  def escalate(member)
    IncidentLifecycleService.new(@workspace).escalate(@incident, escalated_to: member, reason: "Paged", changed_by: nil)
  end

  test "whoever is on call may decide only when the rule says so" do
    escalate(@bob)

    assert approval(on_call: true).approver?(@bob)
    assert_not approval(on_call: false).approver?(@bob)
  end

  test "whoever is on call is asked only when none of the approvers is working the incident" do
    escalate(@bob)
    asked = approval(on_call: true)
    assert_equal [ @bob ], asked.on_call_to_ask

    @incident.lead = @admin
    assert_empty asked.reload.on_call_to_ask
    assert_empty approval(on_call: false).on_call_to_ask
  end

  test "an incident nobody was escalated on has nobody on call to ask" do
    assert_empty approval(on_call: true).on_call_to_ask
  end

  test "the rule's outcome keeps the on-call choice and refuses anything but true or false" do
    assert_empty PolicyRule::ApprovalOutcome.errors_for(PolicyRule::ApprovalOutcome.build(role: "admin", on_call: true))
    assert_includes PolicyRule::ApprovalOutcome.errors_for({ "require" => { "role" => "admin", "count" => 1, "on_call" => "yes" } }),
                    "on_call must be true or false"
  end

  test "the request goes to whoever is on call directly when nobody in the incident can decide" do
    escalate(@bob)
    adapter = mock
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:post_approval_request).returns(message_id: "1.1", channel_id: "C1") if @workspace.incidents_channel_id.present?
    adapter.expects(:post_approval_request_to_user).with { |user_id:, **| user_id == @bob.platform_user_id }.returns(message_id: "1.2", channel_id: "D1")

    ApprovalNotificationService.post!(approval(on_call: true))
  end

  test "someone escalated to after a request was made is asked once, and never while an approver works the incident" do
    adapter = mock
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.stubs(:post_approval_request).returns(message_id: "1.1", channel_id: "C1")
    waiting = approval(on_call: true)
    ApprovalNotificationService.post!(waiting)
    adapter.expects(:post_approval_request_to_user).with { |user_id:, **| user_id == @bob.platform_user_id }.once.returns(message_id: "1.2", channel_id: "D1")

    perform_enqueued_jobs(only: OnCallApprovalsJob) { escalate(@bob) }
    perform_enqueued_jobs(only: OnCallApprovalsJob) { escalate(@bob) }

    assert_equal [ @bob.id ], waiting.reload.asked_member_ids
  end

  test "someone escalated to while an approver leads the incident is not asked" do
    WorkspaceAdapter.stubs(:for).returns(stub(post_approval_request: { message_id: "1.1", channel_id: "C1" }))
    waiting = approval(on_call: true)
    @incident.lead = @admin

    perform_enqueued_jobs(only: OnCallApprovalsJob) { escalate(@bob) }

    assert_empty waiting.reload.asked_member_ids
  end
end
