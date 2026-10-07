require "test_helper"

class WorkspaceAiAccountRecheckJobTest < ActiveJob::TestCase
  test "an account set aside is checked again, and one that answers is used again without telling anyone" do
    workspace = workspaces(:slack_workspace_one)
    refilled = add_ai_account!(workspace, label: "Refilled", out_of_credit_since: 2.hours.ago)
    still_dry = add_ai_account!(workspace, label: "Still dry", out_of_credit_since: 2.hours.ago)
    working = add_ai_account!(workspace, label: "Working")
    checked = []
    FirefightAi.stubs(:check_account).with do |choice, workspace:|
      checked << choice.payer.account.label
      raise FirefightAi::OutOfCredit, "still out" if choice.payer.account.label == "Still dry"

      true
    end

    assert_no_enqueued_jobs(only: WorkspaceAiAccountNoticeJob) { WorkspaceAiAccountRecheckJob.perform_now }

    assert_equal [ "Refilled", "Still dry" ], checked.sort
    assert_equal :verified, refilled.reload.state
    assert_equal :out_of_credit, still_dry.reload.state
    assert_equal :unchecked, working.reload.state
  end
end
