require "test_helper"

class FirefightAi::PostmortemGeneratorTest < ActiveSupport::TestCase
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

  test "generate returns a draft with every section and the model, and persists nothing" do
    stub_ruby_llm_response

    draft = nil
    assert_no_difference [ "Postmortem.count", "IncidentEvent.count" ] do
      draft = @generator.generate(@incident)
    end

    assert_equal "INC-003 Postmortem: Image upload broken", draft.title
    assert draft.sections.key?("summary")
    assert draft.sections.key?("action_items")
    assert_equal FirefightAi::Schemas::Postmortem::SECTION_KEYS.sort, draft.sections.keys.sort
    assert draft.model.present?
  end

  test "generate records an Inference row with the postmortem_generate feature" do
    stub_ruby_llm_response

    assert_difference "Inference.count", 1 do
      @generator.generate(@incident)
    end

    inference = Inference.find_by!(feature: "postmortem_generate", inferable: @incident)
    assert_equal @incident, inference.inferable
  end

  test "client errors leave the engine as its own error family" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    RubyLLM.stubs(:chat).raises(RubyLLM::ContextLengthExceededError.new("too long"))

    error = assert_raises(FirefightAi::TerminalError) { @generator.generate(@incident) }
    assert_equal "ContextLengthExceededError", error.reason
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
