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

  test "an incident is one kind of subject, not the only kind the record allows" do
    runbook = @workspace.runbooks.create!(name: "Pool triage", slug: "pool-triage", position: 1)

    investigation = @workspace.investigations.create!(
      subject: runbook, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400
    )

    assert_equal runbook, investigation.subject
    assert_nil investigation.incident, "a subject that is not an incident has no incident to name"
    assert_nil investigation.incident_id, "the ledger gets nil rather than a foreign id"
    assert_nil investigation.channel_id, "and there is nowhere to post anything"
  end

  test "one live run per subject, counted per subject and not per workspace" do
    runbook = @workspace.runbooks.create!(name: "Pool triage", slug: "pool-triage", position: 1)
    build_investigation

    assert_nothing_raised do
      @workspace.investigations.create!(
        subject: runbook, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400
      )
    end
  end

  test "a subject with no seeder says so rather than storing an empty pack" do
    runbook = @workspace.runbooks.create!(name: "Pool triage", slug: "pool-triage", position: 1)
    investigation = @workspace.investigations.create!(
      subject: runbook, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400
    )

    error = assert_raises(Investigation::Seeding::UnknownSubject) { investigation.build_seed_pack! }

    assert_match "Runbook", error.message
    assert_empty investigation.reload.seed_pack
  end

  test "an incident subject resolves to the incident seeder" do
    assert_equal "Investigation::IncidentSeed", Investigation::Seeding::SEEDERS.fetch("Incident")
  end

  private

  def build_investigation(max_turns: 10, max_spend_cents: 400)
    @workspace.investigations.create!(
      subject: @incident,
      trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: max_turns,
      max_spend_cents: max_spend_cents
    )
  end
end
