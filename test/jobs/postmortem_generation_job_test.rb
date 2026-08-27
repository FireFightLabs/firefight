require "test_helper"

class PostmortemGenerationJobTest < ActiveSupport::TestCase
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

  test "generates when the placeholder says a generation is running" do
    Postmortem.start_generation!(@incident, by: @member)
    PostmortemGenerationService.any_instance.expects(:generate!).with(@incident, generated_by: @member).once

    PostmortemGenerationJob.perform_now(@incident.id)
  end

  test "does nothing without a placeholder, so a stray job cannot overwrite a document" do
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)
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
    PostmortemGenerationJob.perform_now(incident.id)
  end

  test "a human setting status to in_progress is not mistaken for a running generation" do
    Postmortem.create!(
      incident: @incident, generated_by: @member, title: "Being written by hand",
      status: Postmortem::STATUS_IN_PROGRESS, content: { "html" => "<p>draft</p>" }
    )
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)

    assert_equal "<p>draft</p>", @incident.reload.postmortem.content["html"]
  end

  test "an entitlement block marks the placeholder failed with a readable reason" do
    Postmortem.start_generation!(@incident, by: @member)
    Entitlements.stubs(:allows?).with(@workspace, Entitlements::AI).returns(false)
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)

    postmortem = @incident.reload.postmortem
    assert postmortem.generation_failed?
    assert_equal "EntitlementBlocked", postmortem.generation_error
  end

  test "a terminal AI failure keeps the placeholder, marked failed with the reason, and it can be retried" do
    Postmortem.start_generation!(@incident, by: @member)
    generator = mock("generator")
    generator.stubs(:generate).raises(FirefightAi::TerminalError.new("too long", reason: "ContextLengthExceededError"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)
    WorkspaceAdapter.stubs(:for).returns(stub(post_postmortem_generation_failed: nil))

    PostmortemGenerationJob.perform_now(@incident.id)

    postmortem = @incident.reload.postmortem
    assert postmortem.generation_failed?
    assert_equal "ContextLengthExceededError", postmortem.generation_error
    assert_equal Postmortem::STATUS_DRAFT, postmortem.status

    assert Postmortem.start_generation!(@incident, by: @member), "a failed generation can be started again"
    assert postmortem.reload.generating?
  end

  test "two starts while one is running yield one job" do
    assert Postmortem.start_generation!(@incident, by: @member)
    assert_nil Postmortem.start_generation!(@incident, by: @member)
  end

  test "blocked entitlement runs no generation and marks the placeholder failed" do
    deny_entitlements!
    Postmortem.start_generation!(@incident, by: @member)
    FirefightAi::PostmortemGenerator.expects(:new).never

    PostmortemGenerationJob.perform_now(@incident.id)

    assert @incident.reload.postmortem.generation_failed?
  end

  test "discards on record not found" do
    FirefightAi::PostmortemGenerator.expects(:new).never
    assert_nothing_raised do
      PostmortemGenerationJob.perform_now(SecureRandom.uuid)
    end
  end

  test "discards terminal AI errors without retry and notifies the requester" do
    Postmortem.start_generation!(@incident, by: @member)
    generator = mock("generator")
    generator.stubs(:generate).raises(FirefightAi::TerminalError.new("too long", reason: "ContextLengthExceededError"))
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)

    adapter = mock("adapter")
    WorkspaceAdapter.stubs(:for).returns(adapter)
    adapter.expects(:post_postmortem_generation_failed)
      .with(has_entries(incident: @incident, reason: "ContextLengthExceededError", retrying: false)).once

    assert_nothing_raised do
      PostmortemGenerationJob.perform_now(@incident.id)
    end
  end
end
