require "test_helper"

class FirefightAi::PostmortemGenerationJobTest < ActiveSupport::TestCase
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

  test "calls generator generate and post_message" do
    generator = mock("generator")
    generator.expects(:generate).once
    generator.expects(:post_message).once
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    FirefightAi::PostmortemGenerationJob.perform_now(@incident.id, @member.id)
  end

  test "skips if postmortem already exists" do
    incident = Incident.create!(
      workspace: @workspace,
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

    FirefightAi::PostmortemGenerator.expects(:new).never
    FirefightAi::PostmortemGenerationJob.perform_now(incident.id, @member.id)
  end

  test "discards on record not found" do
    FirefightAi::PostmortemGenerator.expects(:new).never
    assert_nothing_raised do
      FirefightAi::PostmortemGenerationJob.perform_now(SecureRandom.uuid, @member.id)
    end
  end
end
