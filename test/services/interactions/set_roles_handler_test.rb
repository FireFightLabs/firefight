require "test_helper"

class Interactions::SetRolesHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles,
           :incident_role_assignments

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @lead_role = incident_roles(:incident_lead_ws1)
    @comms_role = incident_roles(:communications_lead_ws1)
  end

  test "assigns a custom role and closes the modal" do
    stub_all_side_effects

    result = Interactions::SetRolesHandler.execute(
      build_interaction(@comms_role => @alice.platform_user_id)
    )

    assert_nil result
    assert_equal @alice, @incident.reload.role_holder(@comms_role)
  end

  test "records a role assigned event naming the role" do
    stub_all_side_effects

    assert_difference "IncidentEvent.count", 1 do
      Interactions::SetRolesHandler.execute(
        build_interaction(@comms_role => @alice.platform_user_id)
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ROLE_ASSIGNED)
    assert_equal @alice, event.actor
    assert_nil event.eventable
    assert_equal @comms_role.slug, event.metadata["role_slug"]
    assert_equal "assigned the #{@comms_role.name} role", event.description
  end

  test "clearing a custom role removes the assignment" do
    stub_all_side_effects
    assert_equal workspace_memberships(:bob_workspace_one), @incident.role_holder(@comms_role)

    Interactions::SetRolesHandler.execute(build_interaction(@comms_role => nil))

    assert_nil @incident.reload.role_holder(@comms_role)
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ROLE_UNASSIGNED)
  end

  test "assigning the lead goes through the lead path" do
    stub_all_side_effects

    Interactions::SetRolesHandler.execute(
      build_interaction(@lead_role => @bob.platform_user_id)
    )

    assert_equal @bob, @incident.reload.lead
    assert @incident.incident_events.exists?(event_type: IncidentEvent::LEAD_ASSIGNED)
  end

  test "clearing an assigned lead returns a block error" do
    stub_all_side_effects
    @incident.assign_role!(@lead_role, @bob)

    result = Interactions::SetRolesHandler.execute(build_interaction(@lead_role => nil))

    assert_equal "errors", result[:response_action]
    assert_equal @lead_role.unassign_blocked_reason, result[:errors][Identifiers.role_block_id(@lead_role)]
    assert_equal @bob, @incident.reload.lead
  end

  test "leaving an unassigned role empty changes nothing" do
    stub_all_side_effects

    assert_no_difference "IncidentEvent.count" do
      assert_nil Interactions::SetRolesHandler.execute(build_interaction(@lead_role => nil))
    end
  end

  test "assigning the person who already holds the role changes nothing" do
    stub_all_side_effects

    assert_no_difference "IncidentEvent.count" do
      Interactions::SetRolesHandler.execute(
        build_interaction(@comms_role => @bob.platform_user_id)
      )
    end
  end

  test "announces every change in one message" do
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_update_message
    stub_post_ephemeral
    scribe = @workspace.incident_roles.create!(name: "Scribe", slug: "scribe", position: 3)

    posted = []
    Slack::Client.stubs(:post_message).with do |args|
      posted << args
      true
    end.returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })

    Interactions::SetRolesHandler.execute(
      build_interaction(@comms_role => @alice.platform_user_id, scribe => @alice.platform_user_id)
    )

    assert_equal @alice, @incident.reload.role_holder(scribe)
    assert_equal 1, posted.size
    assert_includes posted.first[:text], @comms_role.name
    assert_includes posted.first[:text], scribe.name
  end

  private

  def build_interaction(selections)
    values = selections.each_with_object({}) do |(role, platform_user_id), result|
      result[Identifiers.role_block_id(role)] = {
        Identifiers::ROLE_SELECT => { "selected_user" => platform_user_id }
      }
    end

    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @alice.platform_user_id,
      callback_id: Identifiers::SET_ROLES_MODAL,
      private_metadata: @incident.id,
      values: values
    )
  end

  def stub_all_side_effects
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_update_message
    stub_post_message
    stub_post_ephemeral
  end
end
