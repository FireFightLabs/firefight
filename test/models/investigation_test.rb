require "test_helper"

class InvestigationTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a new run is live so a second request can attach to it" do
    investigation = build_investigation

    assert_equal Investigation::STATUS_PENDING, investigation.status
    assert investigation.live?
    assert_not investigation.over?
  end

  test "only one live run exists per incident" do
    build_investigation

    assert_raises(ActiveRecord::RecordNotUnique) { build_investigation }
  end

  test "a finished run leaves room for the next one" do
    first = build_investigation
    first.claim_running!
    first.finish!(status: Investigation::STATUS_SUCCEEDED)

    assert build_investigation.live?
  end

  test "claiming a run wins exactly once" do
    investigation = build_investigation
    other_worker = Investigation.find(investigation.id)

    assert investigation.claim_running!
    assert_not other_worker.claim_running!
    assert_equal Investigation::STATUS_RUNNING, investigation.status
  end

  test "a run that failed before it was claimed still lands somewhere terminal" do
    investigation = build_investigation

    assert investigation.finish!(status: Investigation::STATUS_FAILED, error_summary: "Boom")
    assert_equal Investigation::STATUS_FAILED, investigation.status
    assert_not_nil investigation.completed_at
  end

  test "finishing a run that is already over changes nothing" do
    investigation = build_investigation
    investigation.finish!(status: Investigation::STATUS_SUCCEEDED)

    assert_not investigation.finish!(status: Investigation::STATUS_FAILED)
    assert_equal Investigation::STATUS_SUCCEEDED, investigation.reload.status
  end

  test "a live status is not a way to finish" do
    investigation = build_investigation

    assert_raises(ArgumentError) { investigation.finish!(status: Investigation::STATUS_RUNNING) }
  end

  test "a run is spent when either half of the budget runs out" do
    investigation = build_investigation(max_turns: 2, max_tokens: 100)

    assert_not investigation.budget_spent?

    investigation.update!(turns_used: 2)
    assert investigation.budget_spent?

    investigation.update!(turns_used: 0, tokens_used: 100)
    assert investigation.budget_spent?
  end

  test "steps are numbered from one" do
    investigation = build_investigation

    assert_equal 1, investigation.next_step_position

    investigation.investigation_steps.create!(
      position: 1,
      action_key: Ability::Action.system_key(
        Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ
      )
    )
    assert_equal 2, investigation.next_step_position
  end

  test "a workspace without the flag cannot investigate" do
    assert_not Investigation.available_for?(@workspace)
    assert_match "not turned on", Investigation.unavailable_reason(@workspace)
  end

  test "a workspace with the flag can investigate" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)

    assert Investigation.available_for?(@workspace)
    assert_nil Investigation.unavailable_reason(@workspace)
  end

  test "entitlements still decide, flag or no flag" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    message = deny_entitlements!

    assert_equal message, Investigation.unavailable_reason(@workspace)
    assert_not Investigation.available_for?(@workspace)
  end

  test "a run needs a trigger source it understands" do
    investigation = build_investigation
    investigation.trigger_source = "telepathy"

    assert_not investigation.valid?
    assert_includes investigation.errors[:trigger_source], "is not included in the list"
  end

  private

  def build_investigation(max_turns: 10, max_tokens: 1_000)
    @workspace.investigations.create!(
      incident: @incident,
      trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: max_turns,
      max_tokens: max_tokens,
      confidence_threshold: 0.7
    )
  end
end
