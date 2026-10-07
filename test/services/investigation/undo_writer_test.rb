require "test_helper"

class Investigation::UndoWriterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @plan = build_fix_plan(@workspace)
    @alice = workspace_memberships(:alice_workspace_one)
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_WEB)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE, result: "Rule 4f2 deleted")
    @plan.steps.where.not(position: 1).update_all(status: Investigation::RemediationStep::STATUS_DONE)
    @plan.settle!
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
  end

  test "an applied fix's undo is written from what its steps did, kept on the same finding, and posted to apply like a fix" do
    FirefightAi::UndoWriter.any_instance.expects(:write).with do |steps, summary:, tools:, **|
      steps.first.result == "Rule 4f2 deleted" && summary == "Remove the rule" && tools == [ "cloudflare_execute" ]
    end.returns("summary" => "Put the rule back", "steps" => [ { "kind" => "action", "description" => "Recreate the rule", "tool" => "cloudflare_execute",
                                                                  "arguments" => { "code" => "create" } } ])
    adapter = mock("adapter")
    adapter.expects(:post_undo_plan).with { |plan:, **| plan.undoes == @plan }.returns({})
    WorkspaceAdapter.stubs(:for).returns(adapter)

    perform_enqueued_jobs(only: InvestigationUndoJob) { assert_nil Investigation::UndoWriter.request!(@plan, by: @alice) }

    undo = @plan.reload.undo_plan
    assert_equal [ "Put the rule back", @plan.finding, Investigation::RemediationPlan::STATUS_PROPOSED ], [ undo.summary, undo.finding, undo.status ]
    assert_equal @plan, @plan.finding.reload.remediation_plan, "the finding's fix is still the fix"
    assert_equal "Its undo is already written, to apply like the fix.", @plan.undo_blocked_reason
    assert_equal "This is already the undo of a fix.", undo.undo_blocked_reason
    assert_nil undo.apply_blocked_reason(@alice)
  end

  test "a writing whose worker was lost can be asked again, nothing that went through needs no undo, and Halon has to be ready" do
    @plan.update_columns(undo_requested_at: 11.minutes.ago)
    assert_nil @plan.reload.undo_blocked_reason
    assert @plan.request_undo!(by: @alice)

    @plan.update_columns(undo_requested_at: nil)
    @plan.steps.update_all(status: Investigation::RemediationStep::STATUS_FAILED)
    assert_equal "Nothing in this fix went through, so there is nothing to undo.", @plan.reload.undo_blocked_reason

    @plan.steps.update_all(status: Investigation::RemediationStep::STATUS_DONE)
    FirefightAi.stubs(:context_window).returns(nil)
    assert_match "not fully set up", @plan.reload.undo_blocked_reason
  end

  test "only an applied fix is undone, once, and an undo the plan's check refuses says why and can be asked again" do
    assert_equal "Only a fix that was applied can be undone.", Investigation::RemediationPlan.new(status: Investigation::RemediationPlan::STATUS_PROPOSED).undo_blocked_reason

    FirefightAi::UndoWriter.any_instance.stubs(:write).returns("summary" => "Put it back", "steps" => [ { "kind" => "action", "description" => "Recreate", "tool" => "nope" } ])
    perform_enqueued_jobs(only: InvestigationUndoJob) { Investigation::UndoWriter.request!(@plan, by: @alice) }

    assert_match "Halon could not write an undo for this fix. Step 1 names \"nope\"", @plan.reload.undo_error
    assert_nil @plan.undo_blocked_reason, "a failed writing can be asked again"
    assert_enqueued_with(job: InvestigationUndoJob) { assert_nil Investigation::UndoWriter.request!(@plan, by: @alice) }
    assert_equal "Halon is writing the undo.", Investigation::UndoWriter.request!(@plan, by: @alice)
  end

  test "an undo the AI account has no credit for says so in plain words, and can be asked again" do
    FirefightAi::UndoWriter.any_instance.stubs(:write).raises(FirefightAi::OutOfCredit.new("OpenRouter refused"))

    perform_enqueued_jobs(only: InvestigationUndoJob) { Investigation::UndoWriter.request!(@plan, by: @alice) }

    assert_equal "Halon cannot write the undo for this fix right now because the AI account behind this Firefight is out of credit. " \
                 "Whoever runs Firefight needs to add credit.", @plan.reload.undo_error
    assert_nil @plan.undo_blocked_reason
  end
end
