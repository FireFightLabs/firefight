require "test_helper"

class FirefightAi::PostmortemSectionRewriterTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @rewriter = FirefightAi::PostmortemSectionRewriter.new(@workspace)
  end

  test "rewrite passes selection and instruction to the LLM and records an Inference row" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)

    captured_prompt = nil
    response = mock("response")
    response.stubs(:content).returns("<p>tightened paragraph</p>")
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(response)
    RubyLLM.stubs(:chat).returns(chat)

    assert_difference "Inference.count", 1 do
      result = @rewriter.rewrite(@incident, selected_html: "<p>original</p>", instruction: "make it tighter")
      assert_equal "<p>tightened paragraph</p>", result
    end

    inference = Inference.order(:created_at).last
    assert_equal "postmortem_rewrite", inference.feature
    assert_equal @incident, inference.inferable

    assert_includes captured_prompt, "<p>original</p>"
    assert_includes captured_prompt, "make it tighter"
  end

  test "rewrite sanitizes script tags and event handlers out of the LLM response" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)

    response = mock("response")
    response.stubs(:content).returns('<p>safe</p><script>alert(1)</script><a href="javascript:bad()" onclick="x()">link</a>')
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:ask).returns(response)
    RubyLLM.stubs(:chat).returns(chat)

    result = @rewriter.rewrite(@incident, selected_html: "<p>x</p>", instruction: "rewrite")

    assert_includes result, "<p>safe</p>"
    assert_not_includes result, "<script"
    assert_not_includes result, "onclick"
    assert_not_includes result, "javascript:"
  end

  test "rewrite includes Layer 2 summary in the prompt when present" do
    summary_stub = OpenStruct.new(content: "Team rolled back deploy 4f2a")
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(summary_stub)

    captured_prompt = nil
    response = mock("response")
    response.stubs(:content).returns("<p>ok</p>")
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(response)
    RubyLLM.stubs(:chat).returns(chat)

    @rewriter.rewrite(@incident, selected_html: "<p>x</p>", instruction: "rewrite")

    assert_includes captured_prompt, "Narrative Summary"
    assert_includes captured_prompt, "rolled back deploy 4f2a"
  end
end
