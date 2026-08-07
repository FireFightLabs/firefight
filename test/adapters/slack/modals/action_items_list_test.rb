require "test_helper"

class Slack::Modals::ActionItemsListTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses,
           :incident_severities, :incident_lifecycle_stages, :incidents

  setup do
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "an open item can be worked without leaving the modal" do
    action = create_action("Restart the worker")

    controls = controls_for(action)

    assert_equal "actions", controls[:type]
    assert_equal [ Identifiers::PICK_UP_ACTION, Identifiers::REASSIGN_ACTION ],
                 controls[:elements].map { |element| element[:action_id] }
  end

  test "an assigned item offers completion and a handover" do
    action = create_action("Restart the worker", assignee: @member)

    assert_equal [ Identifiers::MARK_ACTION_DONE, Identifiers::REASSIGN_ACTION ],
                 controls_for(action)[:elements].map { |element| element[:action_id] }
  end

  test "a completed item is listed without controls" do
    action = create_action("Restart the worker", assignee: @member)
    action.update!(status: IncidentAction::STATUS_DONE)

    assert_nil controls_for(action)
    assert_match "1 completed", blocks.to_s
  end

  test "the modal carries its incident the way every other modal does" do
    view = Slack::Modals::ActionItemsList.build(@incident, kind: :action)

    assert_equal @incident.id, Slack::PrivateMetadata.parse(view[:private_metadata]).incident_id
  end

  test "a long list stays inside Slack's block ceiling and says what it held back" do
    (Slack::Modals::ActionItemsList::MAX_OPEN_ITEMS + 3).times { |index| create_action("Item #{index}") }
    (Slack::Modals::ActionItemsList::MAX_DONE_ITEMS + 2).times do |index|
      create_action("Done #{index}", assignee: @member).update!(status: IncidentAction::STATUS_DONE)
    end

    assert blocks.size <= 100, "a modal may not exceed 100 blocks"
    assert_match "3 more open", blocks.to_s
  end

  private

  def blocks
    Slack::Modals::ActionItemsList.build(@incident.reload, kind: :action)[:blocks]
  end

  def controls_for(action)
    blocks.find do |block|
      block[:type] == "actions" && block[:block_id] == "#{Identifiers::ACTION_BLOCK_PREFIX}#{action.id}"
    end
  end

  def create_action(description, assignee: nil)
    @incident.incident_actions.create!(
      created_by: @member, assignee: assignee, description: description,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      status: assignee ? IncidentAction::STATUS_IN_PROGRESS : IncidentAction::STATUS_OPEN
    )
  end
end
