require "test_helper"

class FirefightAi::PostmortemGeneratorTest < ActiveSupport::TestCase
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
      name: "Test postmortem incident",
      is_private: false,
      channel_id: "C_PM_TEST",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
    @generator = FirefightAi::PostmortemGenerator.new(@workspace)
  end

  test "generate creates postmortem record" do
    stub_ruby_llm_response

    assert_difference "Postmortem.count", 1 do
      @generator.generate(@incident, generated_by: @member)
    end

    postmortem = @incident.reload.postmortem
    assert_equal Postmortem::STATUS_DRAFT, postmortem.status
    assert_equal @member, postmortem.generated_by
    assert_equal "INC-003 Postmortem: Image upload broken", postmortem.title
    assert postmortem.content["html"].present?
  end

  test "generate creates postmortem update snapshot" do
    stub_ruby_llm_response

    assert_difference "PostmortemUpdate.count", 1 do
      @generator.generate(@incident, generated_by: @member)
    end

    update = @incident.postmortem.postmortem_updates.first
    assert_equal PostmortemUpdate::GENERATED, update.update_type
    assert_equal @member, update.edited_by
    assert_equal @incident.postmortem.title, update.title
    assert_equal @incident.postmortem.content, update.content
  end

  test "generate creates POSTMORTEM_GENERATED incident event" do
    stub_ruby_llm_response

    assert_difference "IncidentEvent.count", 1 do
      @generator.generate(@incident, generated_by: @member)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::POSTMORTEM_GENERATED)
    assert_equal @member, event.actor
    assert_instance_of PostmortemUpdate, event.eventable
  end

  test "post_message posts and pins message" do
    stub_ruby_llm_response
    @generator.generate(@incident, generated_by: @member)

    stub_post_message
    stub_pin_message

    result = @generator.post_message(@incident)

    assert_equal "1234567890.123456", result[:message_ts]
    assert_equal "1234567890.123456", @incident.postmortem.reload.message_ts
  end

  test "post_message returns nil when no postmortem exists" do
    assert_nil @generator.post_message(@incident)
  end

  private

  def stub_ruby_llm_response
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)

    ai_result = {
      "title" => "INC-003 Postmortem: Image upload broken",
      "summary" => "**Problem**: Image uploads returning 500 errors.",
      "introduction" => "On the morning of the incident...",
      "deeper_dive" => "Root cause analysis revealed...",
      "impact" => "All users were affected...",
      "resolution" => "1. Corrected the bucket policy\n2. Deployed fix",
      "contributing_factors" => "- S3 bucket policy changed without review",
      "what_went_well" => "- Quick detection via user reports",
      "action_items" => "- Add integration test for upload flow"
    }

    mock_response = mock("response")
    mock_response.stubs(:content).returns(ai_result)

    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_schema).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)
  end

  test "user_prompt includes Narrative Summary section when summary is present" do
    summary_stub = OpenStruct.new(content: "Team rolled back deploy 4f2a")
    data = {
      identifier: "INC-X", name: "n", severity: "minor", status: "resolved",
      declared_at: "x", declared_by: "alice"
    }

    prompt = @generator.send(:user_prompt, data, summary_stub)

    assert_includes prompt, "Narrative Summary"
    assert_includes prompt, "rolled back deploy 4f2a"
  end

  test "user_prompt omits Narrative Summary when summary is nil" do
    data = {
      identifier: "INC-X", name: "n", severity: "minor", status: "resolved",
      declared_at: "x", declared_by: "alice"
    }

    prompt = @generator.send(:user_prompt, data, nil)

    assert_not_includes prompt, "Narrative Summary"
  end

  test "user_prompt caps timeline events" do
    cap = FirefightAi::PostmortemGenerator::MAX_TIMELINE_EVENTS
    events = Array.new(cap + 50) { |i| { at: "t#{i}", description: "event #{i}", by: "system" } }
    data = {
      identifier: "INC-X", name: "n", severity: "minor", status: "resolved",
      declared_at: "x", declared_by: "alice",
      timeline_events: events
    }

    prompt = @generator.send(:user_prompt, data, nil)

    assert_includes prompt, "50 earlier events elided"
  end
end
