require "test_helper"

class FirefightAi::UndoWriterTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "the model is told what each step did, and its answer comes back as a fix the app can check" do
    asked = nil
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).with { |text| asked = text }.returns(llm_reply(content: {
      "summary" => "Put the rule back", "verify" => "Rule 4f2 is listed again",
      "steps" => [ { "kind" => "action", "description" => "Recreate the rule", "repository" => "", "tool" => "cloudflare_execute",
                     "arguments" => "{\"code\":\"create\"}", "missing" => "", "depends_on" => [] } ]
    }, input: 200, output: 80, cost: 0.0002))
    RubyLLM.stubs(:chat).returns(chat)
    step = FirefightAi::UndoWriter::Step.new(position: 1, kind: "action", description: "Delete the rule", repository: nil, tool: "cloudflare_execute",
                                             arguments: { "code" => "delete" }, result: "Rule 4f2 deleted", undo: "Add the rule back", status: "done")

    fix = FirefightAi::UndoWriter.new(@workspace).write([ step ], summary: "Remove the rule", tools: [ "cloudflare_execute" ], inferable: @incident)

    assert_equal({ "summary" => "Put the rule back", "verify" => "Rule 4f2 is listed again",
                   "steps" => [ { "kind" => "action", "description" => "Recreate the rule", "tool" => "cloudflare_execute",
                                  "arguments" => { "code" => "create" }, "depends_on" => [] } ] }, fix)
    assert_match %r{What came back:\n<tool_result tool="cloudflare_execute"[^>]*>.*Rule 4f2 deleted}m, asked
    assert_includes asked, "Undo note: Add the rule back"
    assert_includes asked, "- cloudflare_execute"
    assert_equal FirefightAi::UndoWriter::FEATURE, Inference.find_by!(inferable: @incident).feature
  end
end
