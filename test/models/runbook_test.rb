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
