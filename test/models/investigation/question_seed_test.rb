require "test_helper"

class Investigation::QuestionSeedTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
  end

  test "a question starts from what was asked and where it points, and looks up the rest only when it needs it" do
    pack = @investigation.build_seed_pack!

    assert_equal "checkout is slow", pack["question"]
    assert pack.key?(Investigation::Seeding::KEY_CLUES)
    assert_empty pack.keys & %w[open_incidents recent_alerts services]
  end

  test "a run with no incident and nothing asked is refused" do
    run = @workspace.investigations.new(trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    assert_not run.valid?
  end
end
