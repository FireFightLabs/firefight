require "test_helper"

# A fix's step that an approval rule held, once approved. Approving it never runs it: Halon reads how things stand now,
# whoever applied the fix is told, and the step runs only when someone presses Run, within the hour.
class Investigation::ApprovedFixStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    @plan = build_fix_plan(@workspace)
    @adapter = stub(post_fix_progress: { message_id: "1.2", channel_id: "C1" }, update_fix_progress: { success: true }, update_investigation_answer: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::FixRunner.apply!(@plan, by: @alice, from: AbilityGateway::SOURCE_WEB) }
    @step = @plan.steps.first
  end

  test "Halon reads how things stand now as whoever applied the fix, and the thread is redrawn with it" do
    Chat::StateCheck.expects(:run).with { |owner:, principal:, **| owner == @step && principal == @alice }
                    .returns(Chat::CurrentState::Report.new(state: "The rule is still there.", change: Chat::CurrentState::UNCHANGED))
    @adapter.expects(:update_fix_progress).at_least_once.returns(success: true)

    perform_enqueued_jobs(only: [ AbilityApprovalResumptionJob, FixStepCheckJob ], at: Time.current) { @step.approval.approve!(by: @alice) }

    assert_equal [ Investigation::RemediationStep::STATUS_APPROVED, "The rule is still there." ], [ @step.reload.status, @step.checked_state ]
    assert_not @step.checking?
  end

  test "Dismiss skips the step, so what waits on it never runs, and its approval can no longer be used" do
    Integrations::McpExecutor.expects(:call).never
    approve

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { assert_nil Investigation::FixRunner.dismiss_approved!(@step, by: @alice) }

    assert_equal [ "skipped", "Dismissed by Alice Smith after it was approved. It did not run." ], [ @step.reload.status, @step.result ]
    assert_equal Ability::Approval::STATUS_DISMISSED, @step.approval.status
    assert_equal "skipped", @plan.steps.reload.second.status
  end

  test "an approval nobody runs within the hour expires, the step says so, and asking again requests a new approval without running" do
    Integrations::McpExecutor.expects(:call).never
    approve

    travel Ability::Approval::RUN_WINDOW + 1.minute do
      perform_enqueued_jobs(only: ApprovedCallExpiryJob) { ApprovedCallExpiryJob.perform_later(@step.approval_id) }
      assert @step.reload.lapsed?
      assert_equal Investigation::RemediationStep::EXPIRED, @step.run_blocked_reason(@alice)
      assert_equal [ Chat::CurrentState::ACTION_ASK_AGAIN, Chat::CurrentState::ACTION_DISMISS ], @step.offers

      old = @step.approval
      assert_nil Investigation::FixRunner.ask_again!(@step, by: @alice)
      assert_equal Investigation::RemediationStep::STATUS_WAITING_APPROVAL, @step.reload.status
      assert @step.approval.pending?
      assert_not_equal old.id, @step.approval_id
      assert_equal({ "kind" => ApprovalResumption::KIND_FIX_STEP, "step_id" => @step.id }, @step.approval.resume_payload)
    end
  end

  test "cancelling the fix withdraws an approval that waited to be run" do
    approve

    Investigation::FixRunner.cancel!(@plan, by: @alice)

    assert_equal "skipped", @step.reload.status
    assert_equal Ability::Approval::STATUS_DISMISSED, @step.approval.status
  end

  test "a fix with no thread tells whoever applied it directly when a step is approved" do
    @plan.finding.investigation.update!(thread_id: nil)
    @adapter.expects(:post_fix_step_to_user).with { |user_id:, step:| user_id == @alice.platform_user_id && step == @step }

    approve
  end

  test "a step someone pressed Run on waits for its own job, and another job of the fix coming back after a stop leaves it" do
    approve
    assert_nil Investigation::FixRunner.run_approved!(@step, by: @alice)

    Investigation::FixRunner.new(@plan).advance!(interrupted_at: 1.minute.ago)

    assert_equal Investigation::RemediationStep::STATUS_RUNNING, @step.reload.status
  end

  private

  def approve
    Chat::StateCheck.stubs(:run).returns(Chat::CurrentState::Report.new(state: "The rule is still there.", change: Chat::CurrentState::UNCHANGED))
    perform_enqueued_jobs(only: [ AbilityApprovalResumptionJob, FixStepCheckJob ], at: Time.current) { @step.approval.approve!(by: @alice) }
    @step.reload
  end
end
