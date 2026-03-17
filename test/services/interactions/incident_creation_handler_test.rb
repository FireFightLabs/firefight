require "test_helper"

class Interactions::IncidentCreationHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "creates incident and returns confirmation modal" do
    stub_create_channel

    IncidentCreationWorkflow.expects(:start!).with do |incident|
      incident.name == "DB Down" && incident.workspace == @workspace
    end.once

    result = nil
    assert_difference "Incident.count", 1 do
      result = Interactions::IncidentCreationHandler.execute(
        build_interaction(severity: "critical", name: "DB Down", summary: "Primary DB offline", visibility: "public")
      )
    end

    assert_equal "update", result[:response_action]
    assert_equal "Incident declared", result[:view][:title][:text]

    incident = Incident.find_by!(name: "DB Down")
    assert_equal @workspace, incident.workspace
    assert_equal @member, incident.declared_by
    assert_equal "critical", incident.incident_severity.slug
    assert_equal "investigating", incident.incident_status.slug
    assert_equal "Primary DB offline", incident.summary
    assert_equal false, incident.is_private
    assert_equal "C12345678", incident.channel_id
  end

  test "confirmation modal contains channel deep link" do
    stub_create_channel

    IncidentCreationWorkflow.stubs(:start!)

    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(name: "Link Test")
    )

    actions = result[:view][:blocks].find { |b| b[:type] == "actions" }
    button = actions[:elements].first
    assert_equal "slack://channel?team=#{@workspace.platform_id}&id=C12345678", button[:url]
    assert_includes button[:text][:text], "Join incident channel"
  end

  test "sets is_private when visibility is private" do
    stub_create_channel

    IncidentCreationWorkflow.stubs(:start!)

    Interactions::IncidentCreationHandler.execute(
      build_interaction(visibility: "private")
    )

    incident = Incident.find_by!(name: "Test Incident")
    assert incident.is_private
  end

  test "returns error for invalid severity" do
    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(severity: "nonexistent")
    )

    assert_equal "errors", result[:response_action]
    assert result[:errors][:severity_block].present?
  end

  test "returns error for unknown workspace member" do
    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(user_id: "U_UNKNOWN")
    )

    assert_equal "errors", result[:response_action]
  end

  private

  def build_interaction(severity: "minor", name: "Test Incident", summary: "Test summary", visibility: "public", user_id: @member.platform_user_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: "view_submission",
      team_id: @workspace.platform_id,
      user_id: user_id,
      callback_id: Identifiers::INCIDENT_CREATION_MODAL,
      values: {
        "name_block" => { "name_input" => { "value" => name } },
        "severity_block" => { Identifiers::INCIDENT_CREATION_SEVERITY_SELECT => { "selected_option" => { "value" => severity } } },
        "summary_block" => { "summary_input" => { "value" => summary } },
        "visibility_block" => { "visibility_select" => { "selected_option" => { "value" => visibility } } }
      }
    )
  end
end
