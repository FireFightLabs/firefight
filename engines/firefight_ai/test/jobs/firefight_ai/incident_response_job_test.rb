require "test_helper"

class FirefightAi::IncidentResponseJobTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "posts threaded reply when thread_ts is present" do
    FirefightAi::IncidentResponder.any_instance.stubs(:answer_question).returns("Here's what's happening...")
    Slack::Client.expects(:post_message).with(
      has_entries(thread_ts: "1234567890.123456")
    ).returns({ ok: true, ts: "9999.9999" })

    FirefightAi::IncidentResponseJob.perform_now(
      @incident.id, @incident.channel_id, "1234567890.123456", "what's going on?"
    )
  end

  test "posts channel message when thread_ts is nil" do
    FirefightAi::IncidentResponder.any_instance.stubs(:answer_question).returns("Here's the catchup...")
    Slack::Client.expects(:post_message).with(
      Not(has_key(:thread_ts)) & has_entry(:text, "Here's the catchup...")
    ).returns({ ok: true, ts: "9999.9999" })

    FirefightAi::IncidentResponseJob.perform_now(
      @incident.id, @incident.channel_id, nil, "Give me a catchup"
    )
  end

  test "blocked entitlement posts nothing and runs no responder" do
    deny_entitlements!
    FirefightAi::IncidentResponder.expects(:new).never
    Slack::Client.expects(:post_message).never

    FirefightAi::IncidentResponseJob.perform_now(
      @incident.id, @incident.channel_id, "1234567890.123456", "what's going on?"
    )
  end

  test "discards on record not found" do
    FirefightAi::IncidentResponder.expects(:new).never
    assert_nothing_raised do
      FirefightAi::IncidentResponseJob.perform_now(SecureRandom.uuid, "C123", nil, "test")
    end
  end
end
