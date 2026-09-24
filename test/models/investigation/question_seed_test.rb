require "test_helper"

class Investigation::QuestionSeedTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
  end

  test "a question with no incident starts from what is open, what fired lately and every service" do
    pack = @investigation.build_seed_pack!

    assert_equal "checkout is slow", pack["question"]
    assert_includes pack["open_incidents"].map { |incident| incident["identifier"] }, incidents(:active_critical_ws1).identifier
    assert pack.key?("recent_alerts")
    assert pack.key?("services")
  end

  test "a run with no incident and nothing asked is refused" do
    run = @workspace.investigations.new(trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    assert_not run.valid?
  end
end
