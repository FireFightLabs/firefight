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

  test "a run another worker is holding cannot be claimed twice" do
    investigation = build_investigation
    investigation.claim!

    assert_not Investigation.find(investigation.id).claim!,
               "a retried job must not run alongside the worker that holds the run"
  end

  test "a run whose worker stopped renewing the lease is picked up" do
    investigation = build_investigation
    investigation.claim!

    travel Investigation::LEASE + 1.minute do
      assert Investigation.find(investigation.id).claim!,
             "a retry after a killed worker has to be able to pick the run up"
    end
  end

  test "the same job coming back takes the run at once, since the queue only hands a job out again once its worker is gone" do
    investigation = build_investigation
    investigation.claim!(by: "job-1")

    assert Investigation.find(investigation.id).claim!(by: "job-1"),
           "a deploy that killed the worker must not leave the run waiting out its lease"
  end

  test "a different job still waits for the lease, since the first worker may only be slow" do
    investigation = build_investigation
    investigation.claim!(by: "job-1")

    assert_not Investigation.find(investigation.id).claim!(by: "job-2")
  end

  test "every time a worker takes the run counts as an attempt" do
    investigation = build_investigation
    investigation.claim!(by: "job-1")
    Investigation.find(investigation.id).claim!(by: "job-1")

    assert_equal 2, investigation.reload.attempts
    assert_not investigation.worn_out?
  end

  test "a run that has been taken too many times is worn out" do
    investigation = build_investigation
    investigation.update!(attempts: Investigation::MAX_ATTEMPTS)
    investigation.claim!(by: "job-1")

    assert investigation.worn_out?
  end

  test "a worker that stumbles gives the run back, so the retry does not wait out the lease" do
    investigation = build_investigation
    investigation.claim!

    assert investigation.release!
    assert Investigation.find(investigation.id).claim!, "the retry arrives seconds later, long before the lease runs out"
  end

  test "only the worker holding the run can give it back" do
    investigation = build_investigation
    investigation.claim!

    assert_not Investigation.find(investigation.id).release!
    assert_not Investigation.find(investigation.id).claim!, "the run is still held by the worker that claimed it"
  end

  test "a run nobody is working on counts as abandoned" do
    expired = build_investigation
    expired.claim!
    held = build_investigation(subject: incidents(:active_major_ws1))
    held.claim!
    travel Investigation::LEASE + 1.minute do
      held.record_turn!(turns_used: 1, spent_micros: 0)

      abandoned = @workspace.investigations.abandoned
      assert_includes abandoned, expired
      assert_not_includes abandoned, held
    end
  end

  test "a run whose job never arrived counts as abandoned, a fresh one does not" do
    fresh = build_investigation
    assert_not_includes @workspace.investigations.abandoned, fresh

    travel Investigation::UNCLAIMED_AFTER + 1.minute do
      assert_includes @workspace.investigations.abandoned, fresh
    end
  end

  test "a finished run is never abandoned" do
    investigation = build_investigation
    investigation.claim!
    investigation.finish!(status: Investigation::STATUS_SUCCEEDED)

    travel Investigation::LEASE + 1.minute do
      assert_not_includes @workspace.investigations.abandoned, investigation
    end
  end

  test "resuming keeps the start time even when the caller's copy is stale" do
    investigation = build_investigation
    stale = Investigation.find(investigation.id)
    investigation.claim!
    started_at = investigation.started_at

    travel Investigation::LEASE + 1.minute do
      assert stale.claim!
    end
    assert_equal started_at.to_i, investigation.reload.started_at.to_i
  end

  test "a worker that never claimed the run writes nothing" do
    investigation = build_investigation
    investigation.claim!

    assert_not Investigation.find(investigation.id).record_turn!(turns_used: 1, spent_micros: 10_000)
  end

  test "a turn is written down only while this worker still holds the run" do
    investigation = build_investigation
    investigation.claim!

    assert investigation.record_turn!(turns_used: 2, spent_micros: 70_000)
    assert_equal 70_000, investigation.reload.spent_micros

    travel Investigation::LEASE + 1.minute do
      Investigation.find(investigation.id).claim!
    end

    assert_not investigation.record_turn!(turns_used: 3, spent_micros: 90_000),
               "the worker that lost the run must not write over the one that took it"
    assert_equal 70_000, investigation.reload.spent_micros
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

  test "every workspace can investigate, with no switch to turn on" do
    assert Investigation.available_for?(@workspace)
    assert_nil Investigation.unavailable_reason(@workspace)
  end

  test "a model whose window is not known cannot run, since nothing about it is assumed" do
    FirefightAi.stubs(:context_window).returns(nil)
    Rails.logger.expects(:warn).with { |line| JSON.parse(line)["event"] == "ai.model_without_context_window" }

    assert_match "not fully set up", Investigation.unavailable_reason(@workspace)
  end

  test "entitlements still decide" do
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
    assert_equal %w[command button conversation mcp dashboard rehearsal alert schedule security_event], Investigation::TRIGGER_SOURCES
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

  test "a run starts with what the workspace remembers about the incident's services, kept encrypted and counted as used once" do
    entry = catalog_entries(:auth_service)
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: entry)
    memory = Chat::Memory.create!(workspace: @workspace, text: "Auth Service keeps sessions in Redis", state: Chat::Memory::STATE_UNCONFIRMED, subject: entry)
    Investigation::IncidentSeed.any_instance.stubs(:gather).returns({})
    Investigation::Clues.any_instance.stubs(:gather).returns({})
    run = build_investigation

    run.build_seed_pack!
    run.build_seed_pack!

    assert_equal [ memory.line ], run.reload.starting_facts[Investigation::Seeding::KEY_MEMORIES]
    assert_not run.seed_pack.key?(Investigation::Seeding::KEY_MEMORIES)
    stored = Investigation.where(id: run.id).pick(Arel.sql("seed_pack::text || seed_notes"))
    assert_not_includes stored, "Auth Service keeps sessions in Redis"
    assert_equal 1, memory.reload.use_count
  end

  test "a rehearsal reads its starting memories without counting a use" do
    memory = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    Investigation::IncidentSeed.any_instance.stubs(:gather).returns({})
    Investigation::Clues.any_instance.stubs(:gather).returns({})
    rehearsal = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true, max_turns: 4, max_spend_cents: 400)

    rehearsal.build_seed_pack!

    assert_equal [ memory.line ], rehearsal.starting_facts[Investigation::Seeding::KEY_MEMORIES]
    assert_equal 0, memory.reload.use_count
  end

  test "a starting memory set aside after the run began is told once, and marked in the facts the run reads again" do
    disputed = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED)
    corrected = Chat::Memory.create!(workspace: @workspace, text: "The primary is db-1", state: Chat::Memory::STATE_CONFIRMED)
    kept = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    deleted = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries twice", state: Chat::Memory::STATE_UNCONFIRMED)
    Investigation::IncidentSeed.any_instance.stubs(:gather).returns({})
    Investigation::Clues.any_instance.stubs(:gather).returns({})
    run = build_investigation
    run.build_seed_pack!
    assert_empty run.untold_memory_changes!

    disputed.dispute!("The session store is Postgres")
    corrected.reject!(by: workspace_memberships(:alice_workspace_one), reason: "Moved", correction: "The primary is db-2")
    deleted.destroy!

    told = run.untold_memory_changes!
    assert_equal 3, told.size
    assert(told.any? { |note| note.include?(disputed.id) && note.include?("The session store is Postgres") })
    assert(told.any? { |note| note.include?(corrected.id) && note.include?("The primary is db-2") })
    assert(told.any? { |note| note.include?(deleted.id) && note.include?("deleted") })
    assert_empty run.reload.untold_memory_changes!

    lines = run.starting_facts[Investigation::Seeding::KEY_MEMORIES]
    assert(lines.any? { |line| line.start_with?(disputed.id) && line.include?("[disputed since this run started") })
    assert(lines.any? { |line| line.start_with?(corrected.id) && line.include?("[corrected since this run started: The primary is db-2]") })
    assert_includes lines, kept.line
  end

  test "a run starts with the instructions for the workspace and the incident's services" do
    entry = catalog_entries(:auth_service)
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: entry)
    workspace_wide = Chat::Instruction.create!(workspace: @workspace, text: "Never restart the primary database")
    own = Chat::Instruction.create!(workspace: @workspace, scope: entry, text: "Check the session store first")
    Investigation::IncidentSeed.any_instance.stubs(:gather).returns({})
    Investigation::Clues.any_instance.stubs(:gather).returns({})

    run = build_investigation
    run.build_seed_pack!

    assert_equal [ workspace_wide.line, own.line ], run.reload.starting_facts[Investigation::Seeding::KEY_INSTRUCTIONS]
    assert_not run.seed_pack.key?(Investigation::Seeding::KEY_INSTRUCTIONS)
  end

  test "an incident subject resolves to the incident seeder" do
    assert_equal "Investigation::IncidentSeed", Investigation::Seeding::SEEDERS.fetch("Incident")
  end

  private

  def build_investigation(subject: @incident, max_turns: 10, max_spend_cents: 400)
    @workspace.investigations.create!(
      subject: subject,
      trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: max_turns,
      max_spend_cents: max_spend_cents
    )
  end
end
