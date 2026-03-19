require "test_helper"

class PostmortemGenerationJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Job test incident",
      is_private: false,
      channel_id: "C_JOB_TEST",
      resolved_at: 1.hour.ago
    )
  end

  test "calls service generate and post_message" do
    service = mock("service")
    service.expects(:generate).once
    service.expects(:post_message).once
    PostmortemGenerationService.stubs(:new).returns(service)

    PostmortemGenerationJob.perform_now(@incident.id, @member.id)
  end

  test "skips if postmortem already exists" do
    # Create a separate closed incident with a postmortem
    incident = Incident.create!(
      workspace: @incident.workspace,
      declared_by: @member,
      incident_status: @incident.incident_status,
      incident_severity: @incident.incident_severity,
      name: "Another incident",
      is_private: false,
      channel_id: "C_WITH_POSTMORTEM",
      resolved_at: 1.hour.ago
    )
    Postmortem.create!(
      incident: incident,
      generated_by: @member,
      title: "Existing",
      content: { "sections" => [] }
    )

    PostmortemGenerationService.expects(:new).never
    PostmortemGenerationJob.perform_now(incident.id, @member.id)
  end

  test "discards on record not found" do
    PostmortemGenerationService.expects(:new).never
    assert_nothing_raised do
      PostmortemGenerationJob.perform_now(SecureRandom.uuid, @member.id)
    end
  end
end
