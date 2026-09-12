require "test_helper"

class Workspace::InvestigationLimitsTest < ActiveSupport::TestCase
  setup { @workspace = workspaces(:slack_workspace_one) }

  test "a workspace that set nothing gets the defaults" do
    limits = @workspace.investigation_limits

    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TURNS, limits.max_turns
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_SPEND_CENTS, limits.max_spend_cents
  end

  test "an override replaces the default for that workspace only" do
    @workspace.update!(investigation_max_turns: 6, investigation_max_spend_cents: 250)

    assert_equal 6, @workspace.investigation_limits.max_turns
    assert_equal 250, @workspace.investigation_limits.max_spend_cents
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TURNS,
                 workspaces(:slack_workspace_two).investigation_limits.max_turns
  end

  test "a zero budget is refused" do
    @workspace.investigation_max_turns = 0

    assert_not @workspace.valid?
    assert_includes @workspace.errors[:investigation_max_turns], "must be greater than 0"
  end

  test "spend is whole cents, so there is no floating point money" do
    @workspace.investigation_max_spend_cents = 12.5

    assert_not @workspace.valid?
    assert_includes @workspace.errors[:investigation_max_spend_cents], "must be an integer"
  end

  test "junk in an override is refused rather than cast to zero" do
    @workspace.investigation_max_spend_cents = "plenty"

    assert_not @workspace.valid?
    assert_includes @workspace.errors[:investigation_max_spend_cents], "is not a number"
  end
end
