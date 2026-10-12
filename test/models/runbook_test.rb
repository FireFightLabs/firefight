require "test_helper"

class RunbookTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @critical = incident_severities(:critical_ws1)
    @major = incident_severities(:major_ws1)

    @scoped_runbook = @workspace.runbooks.create!(
      name: "Database outage response",
      summary: "Steps to triage a database outage",
      external_url: "https://runbooks.example.com/db"
    )
    @scoped_runbook.runbook_steps.create!(title: "Check connection pool", position: 1)
    @scoped_runbook.runbook_steps.create!(title: "Failover to replica", position: 2)

    @generic_runbook = @workspace.runbooks.create!(name: "Generic incident checklist")

    @deleted_runbook = @workspace.runbooks.create!(name: "Retired runbook")
    @deleted_runbook.update!(deleted_at: 1.day.ago)
  end

  test "a watch step that reads a status is refused on save without what counts as done" do
    runbook = @workspace.runbooks.new(name: "Deploy", watch: { "title" => "web", "steps" => [ { "label" => "Web", "capability" => "resource_status", "resource" => "web" } ] })

    assert_not runbook.valid?
    assert_match "what counts as done", runbook.errors[:watch].join
  end

  test "a refused watch names each item that is short of something by its name, or by its number when it has none" do
    named = { "label" => "Release", "capability" => "run_history", "resource" => "firefight" }
    unplaced = { "label" => "Deploy finished", "capability" => "resource_status" }
    runbook = @workspace.runbooks.new(name: "Deploy", watch: { "title" => "web", "steps" => [ named, unplaced ] })
    assert_not runbook.valid?
    assert_equal [ "Watch 'Deploy finished': needs the capability to check and the resource, or a read tool" ], runbook.errors.full_messages
    assert_equal runbook.errors.full_messages, runbook.errors[:watch], "the settings page shows the same sentence"

    undecided = { "capability" => "resource_status", "resource" => "web" }
    runbook.watch = { "title" => "web", "steps" => [ undecided, named, undecided.merge("label" => " ") ] }
    assert_not runbook.valid?
    assert_equal [ "Watch 1: needs what counts as done (done when, failed when or a goal)", "Watch 3: needs what counts as done (done when, failed when or a goal)" ],
                 runbook.errors.full_messages
    assert_no_match(/step/i, runbook.errors.full_messages.join)
  end

  test "a watch item may wait for a new deploy named by an input, and only in words" do
    rollout = { "label" => "Web rollout", "capability" => "resource_status", "resource" => "web", "goal" => "web serves the new version",
                "new_deploy" => { "commit" => "{{commit}}", "environment" => "production" } }
    runbook = @workspace.runbooks.new(name: "Ship", inputs: [ { "key" => "commit", "question" => "Which commit?" } ], watch: { "title" => "web", "steps" => [ rollout ] })
    assert runbook.valid?, runbook.errors.full_messages.to_sentence
    runbook.save!
    assert_equal({ "commit" => "f23b4dc", "environment" => "production" }, runbook.filled_watch("commit" => "f23b4dc")["steps"].sole["new_deploy"])

    runbook.watch = { "title" => "web", "steps" => [ rollout.merge("new_deploy" => "the latest") ] }
    assert_equal [ "Watch 'Web rollout': needs the new deploy it waits for as words, such as a commit, a tag or a branch" ], runbook.tap(&:validate).errors[:watch]
  end

  test "a watch item may wait for items before it, by their names or numbers, and only those" do
    run = { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "release" }
    rollout = { "label" => "Web rollout", "capability" => "resource_status", "resource" => "web", "goal" => "web serves the new version", "waits_for" => [ "Release run" ] }
    health = { "capability" => "search_logs", "resource" => "web", "goal" => "no errors", "waits_for" => [ 2 ] }
    runbook = @workspace.runbooks.new(name: "Ship", watch: { "title" => "release", "steps" => [ run, rollout, health ] })
    assert runbook.valid?, runbook.errors.full_messages.to_sentence

    runbook.watch = { "title" => "release", "steps" => [ run.merge("waits_for" => [ "Web rollout" ]), rollout, health.merge("waits_for" => [ "Deploy" ]) ] }
    assert_equal [ "Watch 'Release run': waits for Web rollout, which does not come before it, and an item waits only for items before it",
                   "Watch 3: waits for Deploy, which is not one of its items" ], runbook.tap(&:validate).errors[:watch]

    runbook.watch = { "title" => "release", "steps" => [ run, rollout.merge("waits_for" => "Release run") ] }
    assert_equal [ "Watch 'Web rollout': needs the items it waits for as a list of their names or numbers" ], runbook.tap(&:validate).errors[:watch]
  end

  test "a watch item can be any read Halon makes in a chat, such as following the release workflow's newest run through the general read" do
    newest = { "label" => "Release workflow", "tool" => "northflank_api_request", "focus" => "data.status",
               "arguments" => { "method" => "GET", "path" => "workflows/release/runs", "query" => { "per_page" => 1 } },
               "goal" => "workflow release's newest run, started for {{version}}, finished" }
    runbook = @workspace.runbooks.new(name: "Release", inputs: [ { "key" => "version", "question" => "Which version?" } ],
                                      watch: { "title" => "Release", "steps" => [ newest ] })

    assert runbook.valid?, runbook.errors.full_messages.to_sentence
    runbook.save!
    assert_equal "workflow release's newest run, started for v2, finished", runbook.filled_watch("version" => "v2")["steps"].sole["goal"]

    runbook.watch = { "title" => "Release", "steps" => [ newest.merge("tool" => "not a tool!") ] }
    assert_equal [ "Watch 'Release workflow': needs the read tool's name as Halon calls it" ], runbook.tap(&:validate).errors[:watch]
    runbook.watch = { "title" => "Release", "steps" => [ newest.except("goal") ] }
    assert_match "needs what counts as done", runbook.tap(&:validate).errors[:watch].join
  end

  test "a watch item's name is optional, and one left without is named after what it reads when the runbook runs" do
    unnamed = { "capability" => "run_history", "resource" => "firefight" }
    named = { "label" => "Web", "capability" => "resource_status", "resource" => "web", "goal" => "web runs {{version}}" }
    tool = { "tool" => "api_request", "capability" => "resource_status", "resource" => "web", "goal" => "done" }
    runbook = @workspace.runbooks.create!(name: "Deploy", inputs: [ { "key" => "version", "question" => "Which version?" } ],
                                          watch: { "title" => "release", "steps" => [ unnamed, named, tool ] })

    assert_nil runbook.reload.watch["steps"].first["label"]
    steps = runbook.filled_watch("version" => "v2")["steps"]
    assert_equal [ "Run history", "Web", "api_request" ], steps.map { |step| step["label"] }
    assert_equal "web runs v2", steps.second["goal"]
    titled = runbook.filled_watch("version" => "v2") { |tool| Chat::Tools.title_for(tool, @workspace) }["steps"]
    assert_equal "Api request", titled.third["label"]
  end

  test "a watch step that follows a run needs nothing more, and one that reads a status saves with a goal" do
    history = { "label" => "Release", "capability" => "run_history", "resource" => "firefight" }
    status = { "label" => "Web", "capability" => "resource_status", "resource" => "web", "goal" => "web runs the new version" }
    runbook = @workspace.runbooks.new(name: "Deploy", watch: { "title" => "release", "steps" => [ history, status ] })

    assert runbook.valid?, runbook.errors.full_messages.to_sentence
  end

  test "generates slug from name on create" do
    runbook = @workspace.runbooks.create!(name: "Payments Are Down!")

    assert_equal "payments_are_down", runbook.slug
  end

  test "assigns position on create" do
    assert @generic_runbook.position.present?
  end

  test "active scope excludes soft-deleted runbooks" do
    assert_includes @workspace.runbooks.active, @generic_runbook
    assert_not_includes @workspace.runbooks.active, @deleted_runbook
  end

  test "runbook_steps returns steps ordered by position" do
    assert_equal [ "Check connection pool", "Failover to replica" ], @scoped_runbook.runbook_steps.map(&:title)
  end

  test "matching returns runbook whose one_of severity condition matches" do
    @scoped_runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ @critical.id ]
    )

    assert_includes Runbook.matching(@workspace, { severity: @critical.id }), @scoped_runbook
    assert_not_includes Runbook.matching(@workspace, { severity: @major.id }), @scoped_runbook
  end

  test "matching leaves an unconditioned runbook off unless it is marked always attach" do
    assert_not_includes Runbook.matching(@workspace, { severity: @critical.id }), @generic_runbook

    @generic_runbook.update!(always_attach: true)
    assert_includes Runbook.matching(@workspace, { severity: @critical.id }), @generic_runbook
    assert_includes Runbook.matching(@workspace, {}), @generic_runbook
  end

  test "matching excludes soft-deleted runbooks" do
    assert_not_includes Runbook.matching(@workspace, {}), @deleted_runbook
  end

  test "slug is reusable after the previous runbook is deleted" do
    first = @workspace.runbooks.create!(name: "Cache eviction storm")
    first.update!(deleted_at: Time.current)

    second = @workspace.runbooks.create!(name: "Cache eviction storm")

    assert_equal first.slug, second.slug
    assert_equal 1, @workspace.runbooks.active.where(slug: second.slug).count
  end

  test "sync_steps! keeps the identity of steps that are sent back with their id" do
    check, failover = @scoped_runbook.runbook_steps.ordered.to_a

    @scoped_runbook.sync_steps!([
      { id: failover.id, title: "Failover to the replica", instruction: "Promote it" },
      { id: check.id, title: "Check connection pool", instruction: nil },
      { title: "Verify writes", instruction: nil }
    ])

    steps = @scoped_runbook.runbook_steps.ordered.to_a
    assert_equal [ failover.id, check.id ], steps.first(2).map(&:id)
    assert_equal [ "Failover to the replica", "Check connection pool", "Verify writes" ], steps.map(&:title)
    assert_equal [ 1, 2, 3 ], steps.map(&:position)
  end

  test "sync_steps! soft-deletes steps left out of the payload and keeps their actions readable" do
    check, failover = @scoped_runbook.runbook_steps.ordered.to_a
    incident = incidents(:active_critical_ws1)
    action = incident.incident_actions.create!(
      created_by: workspace_memberships(:alice_workspace_one), action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: check.title, status: IncidentAction::STATUS_OPEN, runbook_step: check
    )

    @scoped_runbook.sync_steps!([ { id: failover.id, title: failover.title, instruction: nil } ])

    assert_equal [ failover.id ], @scoped_runbook.runbook_steps.map(&:id)
    assert check.reload.deleted?
    assert_equal check.id, action.reload.runbook_step_id
    assert_equal check.title, action.runbook_step.title
  end

  test "sync_steps! ignores an id that belongs to another runbook" do
    foreign = @generic_runbook.runbook_steps.create!(title: "Not yours", position: 1)

    @scoped_runbook.sync_steps!([ { id: foreign.id, title: "Copied title", instruction: nil } ])

    assert_equal "Not yours", foreign.reload.title
    assert_equal @generic_runbook.id, foreign.runbook_id
    assert_equal [ "Copied title" ], @scoped_runbook.runbook_steps.map(&:title)
  end
end
