require "test_helper"

class Workspace::InvestigationLimitsTest < ActiveSupport::TestCase
  setup { @workspace = workspaces(:slack_workspace_one) }

  test "a workspace that set nothing gets the defaults" do
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TURNS, @workspace.investigation_turn_limit
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TOKENS, @workspace.investigation_token_limit
    assert_in_delta Workspace::INVESTIGATION_DEFAULT_CONFIDENCE_THRESHOLD,
                    @workspace.investigation_confidence_bar, 0.001
  end

  test "an override replaces the default for that workspace only" do
    @workspace.update!(
      investigation_max_turns: 6, investigation_max_tokens: 50_000,
      investigation_confidence_threshold: 0.85
    )

    assert_equal 6, @workspace.investigation_turn_limit
    assert_equal 50_000, @workspace.investigation_token_limit
    assert_in_delta 0.85, @workspace.investigation_confidence_bar, 0.001
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TURNS,
                 workspaces(:slack_workspace_two).investigation_turn_limit
  end

  test "a budget of zero is refused, since it would mean a run that cannot read anything" do
    @workspace.investigation_max_turns = 0

    assert_not @workspace.valid?
    assert_includes @workspace.errors[:investigation_max_turns], "must be greater than 0"
  end

  test "a confidence bar above one is refused" do
    @workspace.investigation_confidence_threshold = 1.5

    assert_not @workspace.valid?
    assert_includes @workspace.errors[:investigation_confidence_threshold],
                    "must be less than or equal to 1"
  end

  test "junk in an integer override is refused rather than cast to zero" do
    @workspace.investigation_max_tokens = "plenty"

    assert_not @workspace.valid?
  end
end
