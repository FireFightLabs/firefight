require "test_helper"

class Incident::LiveSignalTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @stream = IncidentChannel.stream_name(@incident.id)
    stub_successful_slack_workflow
  end

  test "a lead assigned as Slack assigns one tells the open page its incident and its timeline changed" do
    IncidentLifecycleService.new(@workspace).assign_lead(@incident, workspace_memberships(:bob_workspace_one), changed_by: @member)

    assert_includes parts_sent, Incident::LiveSignal::PART_INCIDENT
    assert_includes parts_sent, Incident::LiveSignal::PART_TIMELINE
  end

  test "nothing is said until the change commits, and nothing at all for one that rolls back" do
    Incident.transaction do
      @incident.update!(summary: "Rolled back")
      assert_no_broadcasts(@stream)
      raise ActiveRecord::Rollback
    end

    assert_no_broadcasts(@stream)

    Incident.transaction do
      @incident.update!(summary: "Kept")
      assert_no_broadcasts(@stream)
    end

    assert_equal [ Incident::LiveSignal::PART_INCIDENT ], parts_sent
  end

  test "an action item completed elsewhere says its items changed, through the guarded move as well" do
    action = IncidentActionService.new(@workspace).create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Roll back the deploy"
    )
    pubsub_adapter.clear_messages(@stream)

    action.move_status!(from: IncidentAction::STATUS_OPEN, to: IncidentAction::STATUS_DONE)

    assert_equal [ Incident::LiveSignal::PART_ACTIONS ], parts_sent
  end

  test "an alert moved between incidents tells both pages" do
    source = AlertSource.create!(workspace: @workspace, name: "Test source", provider: AlertSource::PROVIDER_GENERIC)
    alert = source.alerts.create!(workspace: @workspace, external_id: "e1", fingerprint: "f1", incident: @incident,
                                  received_at: 5.minutes.ago, last_seen_at: 5.minutes.ago)
    other = incidents(:active_major_ws1)
    pubsub_adapter.clear_messages(@stream)

    alert.update!(incident: other)

    assert_equal [ Incident::LiveSignal::PART_INCIDENT ], parts_sent
    assert_broadcasts IncidentChannel.stream_name(other.id), 1
  end

  test "a postmortem's words saved as someone writes leave the page alone" do
    postmortem = Postmortem.start_blank!(@incident, by: @member)
    pubsub_adapter.clear_messages(@stream)

    postmortem.update!(content: { "html" => "<p>Still writing</p>" })

    assert_no_broadcasts(@stream)
  end

  private

  def parts_sent
    broadcasts(@stream).map { |message| ActiveSupport::JSON.decode(message)["part"] }.uniq
  end
end
