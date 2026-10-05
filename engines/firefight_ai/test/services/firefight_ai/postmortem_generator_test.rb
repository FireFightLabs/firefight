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

  test "every key is present for strict output, and every section may be null" do
    schema = FirefightAi::Schemas::Postmortem.new.to_json_schema
    properties = schema.fetch("properties")

    assert_equal ([ "title" ] + FirefightAi::Schemas::Postmortem::SECTION_KEYS).sort, schema.fetch("required").sort
    FirefightAi::Schemas::Postmortem::SECTION_KEYS.each do |key|
      assert_includes properties[key].fetch("anyOf").map { |variant| variant["type"] }, "null", key
    end
    assert_nil properties["title"]["anyOf"]
  end

  test "sections the model returns as null are absent from the draft rather than blank" do
    stub_ruby_llm_response(ai_result: { "title" => "INC-003 Postmortem: Thin", "introduction" => "Declared and resolved.", "summary" => nil, "impact" => nil })

    draft = @generator.generate(@incident)

    assert_equal [ "introduction" ], draft.sections.keys
    assert_nil draft.summary
  end

  test "the prompt says only what is known about the channel, and never that nothing was posted" do
    prompt = @generator.send(:user_prompt, @incident.to_full_context(workspace: @workspace), nil, channel_messages: false)

    assert_match "Firefight holds no messages that people wrote in the incident channel", prompt
    assert_no_match(/No messages were posted/, prompt)
    assert_match "Never infer a cause", @generator.send(:system_prompt)

    unsummarized = @generator.send(:user_prompt, @incident.to_full_context(workspace: @workspace), nil, channel_messages: true)
    assert_match "could not be summarized", unsummarized
    assert_match "Do not read its absence as nothing having been said", unsummarized
  end

  # An incident run from a chat posts its findings as updates and nobody types in the channel. The model used to be
  # handed "updated the incident" five times and told nothing was posted, and wrote a thin document.
  test "an incident run through posted updates hands the model every update, and its timeline names what each said" do
    stub_ruby_llm_response
    updates = [
      "Opened FIR-105 to track the probing: https://linear.app/firefight/issue/FIR-105",
      "Findings so far.\n\n- Probe bursts at 01:30 and 05:28 UTC\n- Every request returned 404\n- Ingress logs are off",
      "Cloudflare rejected the first ruleset change with error 20127.",
      "Traffic came through Cloudflare, but the origin port is public. Recommend restricting it to Cloudflare.",
      "Ruleset v79 now blocks the probed paths and source IPs."
    ]
    @incident.record_change!(IncidentEvent::INCIDENT_CREATED, by: @member)
    @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: @member, message: updates.first) do
      @incident.update!(incident_severity: incident_severities(:major_ws1))
    end
    updates.drop(1).each { |message| @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: @member, message: message) }

    draft = @generator.generate(@incident)

    prompt = draft.prompt
    assert_no_match(/No messages were posted/, prompt)
    assert_match "## Status Updates", prompt
    assert_match "> - Every request returned 404", prompt
    assert_match "> Ruleset v79 now blocks the probed paths and source IPs.", prompt
    assert_match "updated the incident (by Alice Smith). Changed Severity from Minor to Major. Posted the status update", prompt
    assert_equal 5, prompt.scan("Posted the status update quoted under Status Updates").size

    timeline = Postmortem::TimelineSection.markdown(@incident)
    assert_match "  - Severity: Minor → Major", timeline
    assert_match "  - Findings so far.", timeline
    assert_no_match(/Every request returned 404/, timeline)
    assert_match "  - Cloudflare rejected the first ruleset change with error 20127.", timeline
  end

  test "actions and follow-ups that track an issue reach the model with their key and link" do
    [ IncidentAction::ACTION_TYPE_ACTION, IncidentAction::ACTION_TYPE_FOLLOWUP ].each_with_index do |kind, index|
      @incident.incident_actions.create!(created_by: @member, action_type: kind, description: "Item #{index}",
                                         external_key: "FIR-#{index}", external_url: "https://linear.app/firefight/issue/FIR-#{index}")
    end

    prompt = @generator.send(:user_prompt, @incident.to_full_context(workspace: @workspace), nil)

    assert_includes prompt, "- [action] Item 0 [FIR-0, https://linear.app/firefight/issue/FIR-0]"
    assert_includes prompt, "- [followup] Item 1 [FIR-1, https://linear.app/firefight/issue/FIR-1]"
  end

  test "client errors leave the engine as its own error family" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    RubyLLM.stubs(:chat).raises(RubyLLM::ContextLengthExceededError.new("too long"))

    error = assert_raises(FirefightAi::TerminalError) { @generator.generate(@incident) }
    assert_equal "ContextLengthExceededError", error.reason
  end

  private

  def stub_ruby_llm_response(ai_result: nil)
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)

    ai_result ||= {
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

    mock_response = llm_reply(content: ai_result)

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
