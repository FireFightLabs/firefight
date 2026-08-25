require "test_helper"

module Ability
  class ApprovalTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    fixtures :workspaces, :users, :workspace_memberships, :api_keys

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @requester = api_keys(:full_access_key)
      @admin = workspace_memberships(:alice_workspace_one)
      @approval = Ability::Approval.create!(
        workspace: @workspace, principal: @requester, principal_label: @requester.principal_label,
        action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
        required_role: WorkspaceMembership.roles[:admin]
      )
    end

    test "digest is deterministic across key ordering and symbol/string keys" do
      a = Ability::Approval.digest("x.y", { "b" => 1, "a" => [ { "d" => 2, "c" => 3 } ] }, { "environment" => "e" })
      b = Ability::Approval.digest("x.y", { a: [ { c: 3, d: 2 } ], b: 1 }, { environment: "e" })
      c = Ability::Approval.digest("x.y", { a: [ { c: 3, d: 2 } ], b: 2 }, { environment: "e" })

      assert_equal a, b
      assert_not_equal a, c
    end

    test "approve! records the approver and is single-use" do
      @approval.approve!(by: @admin)

      assert @approval.approved?
      assert_equal @admin, @approval.approver
      assert @approval.usable?

      @approval.consume!
      assert_not @approval.usable?
      assert_raises(Ability::Approval::NotAllowed) { @approval.consume! }
    end

    test "two copies of the same approval cannot both consume it" do
      @approval.approve!(by: @admin)
      first = Ability::Approval.find(@approval.id)
      second = Ability::Approval.find(@approval.id)

      first.consume!

      assert_raises(Ability::Approval::NotAllowed) { second.consume! }
      assert_equal first.consumed_at.to_i, @approval.reload.consumed_at.to_i
    end

    test "approver must hold the required role at click time" do
      member = workspace_memberships(:bob_workspace_one)

      error = assert_raises(Ability::Approval::NotAllowed) { @approval.approve!(by: member) }
      assert_match(/admin/, error.message)
      assert @approval.pending?
    end

    test "resolution requires a pending approval" do
      @approval.deny!(by: @admin)

      assert_raises(Ability::Approval::NotAllowed) { @approval.approve!(by: @admin) }
      assert @approval.denied?
    end

    test "requesters approve their own agent's request by default (human-in-the-loop)" do
      approval = Ability::Approval.create!(
        workspace: @workspace, principal: @admin, principal_label: @admin.principal_label,
        action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
        required_role: WorkspaceMembership.roles[:admin]
      )

      approval.approve!(by: @admin)
      assert approval.approved?
    end

    test "four-eyes policies block self-approval" do
      approval = Ability::Approval.create!(
        workspace: @workspace, principal: @admin, principal_label: @admin.principal_label,
        action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
        required_role: WorkspaceMembership.roles[:admin], self_approvable: false
      )

      error = assert_raises(Ability::Approval::NotAllowed) { approval.approve!(by: @admin) }
      assert_match(/someone other than the requester/, error.message)
    end

    test "expire! only touches pending approvals" do
      @approval.expire!
      assert_equal Ability::Approval::STATUS_EXPIRED, @approval.status

      @approval.update!(status: Ability::Approval::STATUS_APPROVED)
      @approval.expire!
      assert @approval.approved?
    end

    test "creating a row directly enqueues no platform traffic" do
      assert_no_enqueued_jobs(only: [ AbilityApprovalNotificationJob, AbilityApprovalResumptionJob ]) do
        Ability::Approval.create!(
          workspace: @workspace, principal: @requester, principal_label: @requester.principal_label,
          action_key: "catalog.create", request_digest: Ability::Approval.digest("catalog.create", {}, {}),
          required_role: WorkspaceMembership.roles[:admin]
        )
      end
    end

    test "resolving a parked chat request enqueues its replay, an unparked one does not" do
      assert_no_enqueued_jobs(only: AbilityApprovalResumptionJob) do
        @approval.approve!(by: @admin)
      end

      parked = Ability::Approval.create!(
        workspace: @workspace, principal: @admin, principal_label: @admin.principal_label,
        action_key: "catalog.create", request_digest: Ability::Approval.digest("catalog.create", {}, {}),
        required_role: WorkspaceMembership.roles[:admin],
        resume_payload: { "kind" => ApprovalResumption::KIND_COMMAND, "attrs" => {}, "channel_id" => "C1", "user_id" => "U1" }
      )
      assert_enqueued_with(job: AbilityApprovalResumptionJob, args: [ { approval_id: parked.id } ]) do
        parked.deny!(by: @admin)
      end
    end

    test "named approvers replace the role" do
      bob = workspace_memberships(:bob_workspace_one)
      @approval.update!(approver_ids: [ bob.id ])

      assert @approval.approver?(bob)
      assert_not @approval.approver?(@admin)
      assert_equal [ bob ], @approval.approvers.to_a

      error = assert_raises(Ability::Approval::NotAllowed) { @approval.approve!(by: @admin) }
      assert_match bob.display_name, error.message

      @approval.approve!(by: bob)
      assert @approval.approved?
    end

    test "without named approvers everyone holding the role is an approver" do
      assert_equal [ @admin ], @approval.approvers.to_a
      assert @approval.approver?(@admin)
      assert_not @approval.approver?(workspace_memberships(:bob_workspace_one))
    end

    test "notify decides where the request is asked" do
      assert @approval.notify_channel?
      assert_not @approval.notify_dm?

      @approval.update!(notify: PolicyRule::ApprovalOutcome::NOTIFY_DM)
      assert_not @approval.notify_channel?
      assert @approval.notify_dm?

      @approval.update!(notify: PolicyRule::ApprovalOutcome::NOTIFY_BOTH)
      assert @approval.notify_channel?
      assert @approval.notify_dm?

      assert_raises(ActiveRecord::RecordInvalid) { @approval.update!(notify: "carrier pigeon") }
    end
  end
end
