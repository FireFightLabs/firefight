require "test_helper"

class PostmortemGenerationServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Service test incident",
      is_private: false,
      channel_id: "C_PM_SERVICE",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
    @draft = FirefightAi::PostmortemGenerator::Draft.new(
      title: "INC-9 Postmortem: Service test",
      summary: "**Problem**: it broke",
      sections: { "summary" => "**Problem**: it broke", "resolution" => "1. Restarted it" },
      model: "gpt-4o"
    )
    generator = mock("generator")
    generator.stubs(:generate).returns(@draft)
    FirefightAi::PostmortemGenerator.stubs(:new).returns(generator)
  end

  test "fills the placeholder from the draft, records the event, posts and pins the announcement" do
    Postmortem.start_generation!(@incident, by: @member)
    stub_post_message
    stub_pin_message

    assert_difference "IncidentEvent.count", 1 do
      PostmortemGenerationService.new(@workspace).generate!(@incident, generated_by: @member)
    end

    postmortem = @incident.reload.postmortem
    assert_equal "INC-9 Postmortem: Service test", postmortem.title
    assert_includes postmortem.content["html"], "<h2>Resolution</h2>"
    assert_includes postmortem.content["html"], "<ol>"
    assert_nil postmortem.generation_state
    assert_equal "gpt-4o", postmortem.model_id
    assert_equal "1234567890.123456", postmortem.message_ts
    assert @incident.incident_events.exists?(event_type: IncidentEvent::POSTMORTEM_GENERATED)
  end

  test "creates the postmortem when no placeholder exists" do
    stub_post_message
    stub_pin_message

    assert_difference "Postmortem.count", 1 do
      PostmortemGenerationService.new(@workspace).generate!(@incident, generated_by: @member)
    end
    assert_equal @member, @incident.reload.postmortem.generated_by
  end

  test "an incident without a channel is saved but not announced" do
    @incident.update!(channel_id: nil)
    WorkspaceAdapter.expects(:for).never

    postmortem = PostmortemGenerationService.new(@workspace).generate!(@incident, generated_by: @member)

    assert postmortem.persisted?
    assert_nil postmortem.message_ts
  end
end
