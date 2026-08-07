require "test_helper"

class Slack::Modals::RunbookDetailTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses,
           :incident_severities, :incident_lifecycle_stages, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @runbook = @workspace.runbooks.create!(name: "Database outage", content: "How we restore writes")
    @step = @runbook.runbook_steps.create!(
      title: "Check the pool", instruction: "Inspect connection count against the limit", position: 1
    )
    @incident_runbook = @incident.incident_runbooks.create!(runbook: @runbook, workspace: @workspace)
  end

  test "a step carries its full instruction, not just its title" do
    section = step_section

    assert_match @step.title, section.dig(:text, :text)
    assert_match @step.instruction, section.dig(:text, :text)
  end

  test "an unclaimed step offers a person picker" do
    assert_equal Identifiers::ASSIGN_RUNBOOK_STEP, step_section.dig(:accessory, :action_id)
    assert_match "Unclaimed", view[:blocks].to_s
  end

  test "a claimed step preselects its holder" do
    claim(@step, @member, IncidentAction::STATUS_IN_PROGRESS)

    assert_equal @member.platform_user_id, step_section.dig(:accessory, :initial_user)
    assert_match "Claimed by <@#{@member.platform_user_id}>", view[:blocks].to_s
  end

  test "a completed step has nothing left to hand out" do
    claim(@step, @member, IncidentAction::STATUS_DONE)

    assert_nil step_section[:accessory]
    assert_match "Completed by <@#{@member.platform_user_id}>", view[:blocks].to_s
  end

  test "the modal carries the attachment so a pick knows what it belongs to" do
    metadata = Slack::PrivateMetadata.parse(view[:private_metadata])
    assert_equal @incident_runbook.id, metadata.incident_runbook_id
    assert_equal @incident.id, metadata.incident_id
    assert_equal Identifiers::RUNBOOK_DETAIL_MODAL, view[:callback_id]
  end

  private

  def view
    Slack::Modals::RunbookDetail.build(@incident_runbook.reload)
  end

  def step_section
    view[:blocks].find { |block| block[:block_id] == "#{Identifiers::RUNBOOK_STEP_BLOCK_PREFIX}#{@step.id}" }
  end

  def claim(step, member, status)
    @incident.incident_actions.create!(
      created_by: member, assignee: member, runbook_step: step,
      action_type: IncidentAction::ACTION_TYPE_ACTION, description: step.title, status: status
    )
  end
end
