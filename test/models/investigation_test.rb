require "test_helper"

class InvestigationTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a new run starts pending and live" do
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
    first.claim!
    first.finish!(status: Investigation::STATUS_SUCCEEDED)

    assert build_investigation.live?
  end

  test "claiming moves a waiting run to running" do
    investigation = build_investigation

    assert investigation.claim!
    assert_equal Investigation::STATUS_RUNNING, investigation.status
    assert_not_nil investigation.started_at
  end

  test "claiming a run that is already running resumes it rather than refusing" do
    investigation = build_investigation
    investigation.claim!

    resumed = Investigation.find(investigation.id)

    assert resumed.claim!, "a retry after a killed worker has to be able to pick the run up"
  end

  test "resuming keeps the start time even when the caller's copy is stale" do
    investigation = build_investigation
    stale = Investigation.find(investigation.id)
    investigation.claim!
    started_at = investigation.started_at

    assert stale.claim!
    assert_equal started_at.to_i, investigation.reload.started_at.to_i
  end

  test "claiming a run that is over does nothing" do
    investigation = build_investigation
    investigation.finish!(status: Investigation::STATUS_SUCCEEDED)

    assert_not investigation.claim!
    assert_equal Investigation::STATUS_SUCCEEDED, investigation.reload.status
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

  test "both entry points share one already running sentence" do
    assert_match @incident.identifier, Investigation.already_running_message(@incident)
  end

  test "a run needs a trigger source it understands" do
    investigation = build_investigation
    investigation.trigger_source = "email"

    assert_not investigation.valid?
    assert_includes investigation.errors[:trigger_source], "is not included in the list"
  end

  test "a trigger source names what happened, not which platform it happened on" do
    assert_equal %w[command button], Investigation::TRIGGER_SOURCES
  end

  private

  def build_investigation(max_turns: 10, max_spend_cents: 400)
    @workspace.investigations.create!(
      incident: @incident,
      trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: max_turns,
      max_spend_cents: max_spend_cents
    )
  end
end
