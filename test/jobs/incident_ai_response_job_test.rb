require "test_helper"

class IncidentAiResponseJobTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "posts the catchup in the channel" do
    FirefightAi::IncidentResponder.any_instance.stubs(:answer_question).returns("Here's the catchup...")
    Slack::Client.expects(:post_message).with(
      Not(has_key(:thread_ts)) & has_entry(:text, "Here's the catchup...")
    ).returns({ ok: true, ts: "9999.9999" })

    IncidentAiResponseJob.perform_now(@incident.id, @incident.channel_id, "Give me a catchup")
  end

  test "a job queued with the arguments it once took still answers the question, in the channel" do
    FirefightAi::IncidentResponder.any_instance.expects(:answer_question).with(@incident, question: "Give me a catchup").returns("Here's the catchup...")
    Slack::Client.expects(:post_message).with(Not(has_key(:thread_ts)) & has_entry(:text, "Here's the catchup...")).returns({ ok: true, ts: "9999.9999" })

    IncidentAiResponseJob.perform_now(@incident.id, @incident.channel_id, "1700000000.000100", "Give me a catchup", nil)
  end

  test "an AI account out of credit is said where the answer would have gone, without naming the provider" do
    FirefightAi::IncidentResponder.any_instance.stubs(:answer_question).raises(FirefightAi::OutOfCredit.new("OpenRouter refused"))
    said = "Halon cannot answer right now because the AI account behind this Firefight is out of credit. Whoever runs Firefight needs to add credit."
    Slack::Client.expects(:post_message).with(has_entries(channel: @incident.channel_id, text: said)).returns({ ok: true, ts: "9999.9999" })

    IncidentAiResponseJob.perform_now(@incident.id, @incident.channel_id, "Give me a catchup")
  end

  test "blocked entitlement posts nothing and runs no responder" do
    deny_entitlements!
    FirefightAi::IncidentResponder.expects(:new).never
    Slack::Client.expects(:post_message).never

    IncidentAiResponseJob.perform_now(@incident.id, @incident.channel_id, "Give me a catchup")
  end

  test "discards on record not found" do
    FirefightAi::IncidentResponder.expects(:new).never
    assert_nothing_raised do
      IncidentAiResponseJob.perform_now(SecureRandom.uuid, "C123", "test")
    end
  end
end
