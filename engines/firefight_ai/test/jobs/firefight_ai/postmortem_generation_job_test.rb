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
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
  end

  test "calls generator generate and post_message" do
    generator = mock("generator")
    generator.expects(:generate).once
    generator.expects(:post_message).once
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    FirefightAi::PostmortemGenerationJob.perform_now(@incident.id, @member.id)
  end

  test "skips when an already-filled postmortem exists" do
    incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @incident.incident_status,
      incident_severity: @incident.incident_severity,
      name: "Another incident",
      is_private: false,
      channel_id: "C_WITH_POSTMORTEM",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
    Postmortem.create!(
      incident: incident,
      generated_by: @member,
      title: "Existing",
      status: Postmortem::STATUS_DRAFT,
      content: { "html" => "already filled" }
    )

    FirefightAi::PostmortemGenerator.expects(:new).never
    FirefightAi::PostmortemGenerationJob.perform_now(incident.id, @member.id)
  end

  test "fills an in_progress placeholder when one exists" do
    Postmortem.create!(
      incident: @incident,
      generated_by: @member,
      title: "Generating placeholder",
      status: Postmortem::STATUS_IN_PROGRESS,
      content: { "html" => "" }
    )

    generator = mock("generator")
    generator.expects(:generate).once
    generator.expects(:post_message).once
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    FirefightAi::PostmortemGenerationJob.perform_now(@incident.id, @member.id)
  end

  test "destroys the in_progress placeholder on terminal AI failure" do
    Postmortem.create!(
      incident: @incident,
      generated_by: @member,
      title: "Generating placeholder",
      status: Postmortem::STATUS_IN_PROGRESS,
      content: { "html" => "" }
    )

    generator = mock("generator")
    generator.stubs(:generate).raises(RubyLLM::ContextLengthExceededError.new("too long"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)
    WorkspaceAdapter.stubs(:for).returns(stub(post_ephemeral: nil))

    FirefightAi::PostmortemGenerationJob.perform_now(@incident.id, @member.id)

    assert_nil @incident.reload.postmortem
  end

  test "blocked entitlement runs no generation and clears the in_progress placeholder" do
    deny_entitlements!
    Postmortem.create!(
      incident: @incident,
      generated_by: @member,
      title: "Generating placeholder",
      status: Postmortem::STATUS_IN_PROGRESS,
      content: { "html" => "" }
    )

    FirefightAi::PostmortemGenerator.expects(:new).never

    FirefightAi::PostmortemGenerationJob.perform_now(@incident.id, @member.id)

    assert_nil @incident.reload.postmortem
  end

  test "discards on record not found" do
    FirefightAi::PostmortemGenerator.expects(:new).never
    assert_nothing_raised do
      FirefightAi::PostmortemGenerationJob.perform_now(SecureRandom.uuid, @member.id)
    end
  end

  test "discards terminal AI errors without retry and notifies the requester" do
    generator = mock("generator")
    generator.stubs(:generate).raises(RubyLLM::ContextLengthExceededError.new("too long"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    adapter = mock("adapter")
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:post_ephemeral).with do |args|
      args[:text].include?("ContextLengthExceeded") && args[:text].include?(@incident.identifier)
    end.once

    assert_nothing_raised do
      FirefightAi::PostmortemGenerationJob.perform_now(@incident.id, @member.id)
    end
  end
end
