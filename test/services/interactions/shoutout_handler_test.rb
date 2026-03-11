require "test_helper"

class Interactions::ShoutoutHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @from_member = workspace_memberships(:alice_workspace_one)
    @to_member = workspace_memberships(:bob_workspace_one)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @from_member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )
  end

  test "creates shoutout record and posts message to channel" do
    stub_post_message

    assert_difference "Shoutout.count", 1 do
      Interactions::ShoutoutHandler.execute(build_interaction)
    end

    shoutout = @incident.shoutouts.find_by!(from_member: @from_member, to_member: @to_member)
    assert_equal "Amazing debugging work!", shoutout.message
  end

  test "returns nil on success" do
    stub_post_message

    result = Interactions::ShoutoutHandler.execute(build_interaction)

    assert_nil result
  end

  test "handles missing incident silently" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @from_member.platform_user_id,
      callback_id: Identifiers::SHOUTOUT_MODAL,
      private_metadata: { incident_id: SecureRandom.uuid }.to_json,
      values: build_values
    )

    assert_no_difference "Shoutout.count" do
      result = Interactions::ShoutoutHandler.execute(interaction)
      assert_nil result
    end
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @from_member.platform_user_id,
      callback_id: Identifiers::SHOUTOUT_MODAL,
      private_metadata: { incident_id: @incident.id }.to_json,
      values: build_values
    )
  end

  def build_values
    {
      "recipient_block" => {
        "recipient_select" => { "selected_user" => @to_member.platform_user_id }
      },
      "message_block" => {
        "message_input" => { "value" => "Amazing debugging work!" }
      }
    }
  end
end
