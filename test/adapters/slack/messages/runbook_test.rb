require "test_helper"

class Slack::Messages::RunbookTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses,
           :incident_severities, :incident_lifecycle_stages, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @runbook = @workspace.runbooks.create!(name: "Database outage", summary: "Restore writes")
    @first = @runbook.runbook_steps.create!(title: "Check the pool", position: 1)
    @second = @runbook.runbook_steps.create!(title: "Failover", position: 2)
    @incident_runbook = @incident.incident_runbooks.create!(runbook: @runbook, workspace: @workspace)
  end

  test "every step gets a row, with no cap at ten" do
    12.times { |index| @runbook.runbook_steps.create!(title: "Extra #{index}", position: index + 3) }

    titles = step_rows.map { |row| row.dig(:text, :text) }

    assert_equal 14, titles.size
    assert_no_match(/more/, blocks.to_s)
  end

  test "an unclaimed step offers to be taken and carries its own identity" do
    row = step_rows.first

    assert_equal :"claim_runbook_step", row.dig(:accessory, :action_id).to_sym
    payload = JSON.parse(row.dig(:accessory, :value))
    assert_equal @first.id, payload["step_id"]
    assert_equal @incident_runbook.id, payload["incident_runbook_id"]
  end

  test "a claimed step shows its holder and offers completion" do
    claim(@first, @member)
    row = step_rows.first

    assert_match "Claimed by <@#{@member.platform_user_id}>", row.dig(:text, :text)
    assert_equal Identifiers::MARK_ACTION_DONE, row.dig(:accessory, :action_id)
  end

  test "a completed step is struck through and loses its button" do
    action = claim(@first, @member)
    action.update!(status: IncidentAction::STATUS_DONE)
    row = step_rows.first

    assert_match "~#{@first.title}~", row.dig(:text, :text)
    assert_nil row[:accessory]
  end

  test "a runbook past the block ceiling says how many steps it held back" do
    (Slack::Messages::Runbook::MAX_STEP_ROWS + 5).times do |index|
      @runbook.runbook_steps.create!(title: "Step #{index}", position: index + 3)
    end

    assert_equal Slack::Messages::Runbook::MAX_STEP_ROWS, step_rows.size
    assert_match "more steps", blocks.to_s
    assert blocks.size <= 50, "a message may not exceed 50 blocks"
  end

  test "the footer offers the detail modal" do
    footer = blocks.last

    assert_equal "actions", footer[:type]
    assert_equal Identifiers::VIEW_RUNBOOK, footer[:elements].first[:action_id]
  end

  private

  def blocks
    Slack::Messages::Runbook.attached(@incident_runbook.reload)
  end

  def step_rows
    blocks.select { |block| block[:block_id].to_s.start_with?(Identifiers::RUNBOOK_STEP_BLOCK_PREFIX) }
  end

  def claim(step, member)
    @incident.incident_actions.create!(
      created_by: member, assignee: member, runbook_step: step,
      action_type: IncidentAction::ACTION_TYPE_ACTION, description: step.title,
      status: IncidentAction::STATUS_IN_PROGRESS
    )
  end
end
