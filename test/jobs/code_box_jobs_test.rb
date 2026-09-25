require "test_helper"

class CodeBoxJobsTest < ActiveJob::TestCase
  test "the idle check lets go of a chat's box only through the idle rule" do
    Integrations::CodeReading.expects(:close_idle).with("conversation-1")

    CodeBoxIdleJob.perform_now("conversation-1")
  end

  test "the sweep hands over to the one place that stops boxes" do
    Integrations::CodeReading.expects(:sweep!)

    CodeBoxSweepJob.perform_now
  end

  test "a chat answer that read code schedules its box's idle check, and one that did not schedules nothing" do
    workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: workspace, member: workspace_memberships(:alice_workspace_one))
    Conversation::Runner.any_instance.stubs(:run)

    ConversationReplyJob.perform_now(conversation.id)
    assert_no_enqueued_jobs(only: CodeBoxIdleJob)

    CodeBox.create!(workspace: workspace, key: conversation.code_box_key, provider: "docker", box_ref: "abc",
                    address: "http://127.0.0.1:9", secret: "k", last_used_at: Time.current)
    assert_enqueued_with(job: CodeBoxIdleJob, args: [ conversation.code_box_key ]) do
      ConversationReplyJob.perform_now(conversation.id)
    end
  end

  test "a finished investigation lets its box go" do
    investigation = workspaces(:slack_workspace_one).investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    Investigation.any_instance.stubs(:build_seed_pack!)
    Investigation::Runner.any_instance.stubs(:run).returns(Investigation::Runner::Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil))
    Integrations::CodeReading.expects(:close).with(investigation.code_box_key)

    InvestigationJob.perform_now(investigation.id)
  end
end
