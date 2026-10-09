require "test_helper"

class FirefightAi::MemoryJudgeTest < ActiveSupport::TestCase
  setup do
    @judge = FirefightAi::MemoryJudge.new(workspaces(:slack_workspace_one))
    @known = [ FirefightAi::MemoryJudge::Known.new(id: "a", text: "web deploys from main"),
               FirefightAi::MemoryJudge::Known.new(id: "b", text: "web runs two instances"),
               FirefightAi::MemoryJudge::Known.new(id: "c", text: "main is the branch web ships from") ]
  end

  test "each remembered fact is judged by its number, and only the same or a contradiction comes back" do
    chat = stub_model(content: { verdicts: [ { number: 1, verdict: "contradicts" }, { number: 2, verdict: "unrelated" }, { number: 3, verdict: "same" } ] })
    chat.expects(:ask).with { |text| text.include?("## The new fact\nweb deploys from the release branch") && text.include?("2. web runs two instances") }
        .returns(llm_reply(content: { verdicts: [ { number: 1, verdict: "contradicts" }, { number: 3, verdict: "same" } ] }, input: 100, output: 20, cost: 0.0001))

    verdicts = @judge.verdicts(fact: "web deploys from the release branch", known: @known)

    assert_equal [ %w[a contradicts], %w[c same] ], verdicts.map { |each| [ each.id, each.verdict ] }
    assert Inference.exists?(feature: FirefightAi::MemoryJudge::FEATURE)
  end

  test "a number it does not know, a verdict it does not know, or nothing known reads as unrelated, and nothing known asks no model" do
    stub_model(content: { verdicts: [ { number: 9, verdict: "contradicts" }, { number: 1, verdict: "maybe" } ] })
    assert_empty @judge.verdicts(fact: "web deploys from main", known: @known)

    RubyLLM.expects(:chat).never
    assert_empty @judge.verdicts(fact: "web deploys from main", known: [])
  end

  private

  def stub_model(content:)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).returns(llm_reply(content: content, input: 100, output: 20, cost: 0.0001))
    RubyLLM.stubs(:chat).returns(chat)
    chat
  end
end
