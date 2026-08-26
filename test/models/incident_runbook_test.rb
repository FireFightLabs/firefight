require "test_helper"

class IncidentRunbookTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)

    @first = attach("Database outage", "Check the pool")
    @second = attach("Cache outage", "Flush the cache")
  end

  test "each attachment sees only its own steps" do
    claim(@first)

    assert_equal [ @first.runbook.runbook_steps.first.id ], @first.actions_by_step.keys
    assert_empty @second.actions_by_step
  end

  test "attachments on one incident share a single load" do
    claim(@first)
    claim(@second)

    incident = Incident.with_detail_associations.find(@incident.id)
    attachments = incident.incident_runbooks.to_a

    # Counted per attachment rather than in total. How many queries the first
    # load costs depends on what else the page preloaded, and that is not what
    # this is about. The second attachment adding none is.
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { attachments.first.actions_by_step }
    assert_operator queries, :>=, 1, "the first attachment should load the incident's step actions"

    queries = 0
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { attachments.last.actions_by_step }

    assert_equal 2, attachments.size
    assert_equal 0, queries, "the second attachment should reuse the first one's load"
  end

  private

  def attach(runbook_name, step_title)
    runbook = @workspace.runbooks.create!(name: runbook_name)
    runbook.runbook_steps.create!(title: step_title, position: 1)
    @incident.incident_runbooks.create!(runbook: runbook, workspace: @workspace)
  end

  def claim(incident_runbook)
    step = incident_runbook.runbook.runbook_steps.first
    @incident.incident_actions.create!(
      created_by: @member, assignee: @member, runbook_step: step,
      action_type: IncidentAction::ACTION_TYPE_ACTION, description: step.title,
      status: IncidentAction::STATUS_IN_PROGRESS
    )
  end
end
