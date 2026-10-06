require "test_helper"

class FirefightAi::LessonExtractorTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @extractor = FirefightAi::LessonExtractor.new(@workspace)
    @sources = [ FirefightAi::LessonExtractor::Source.new(title: "Summary", text: "The pool ran dry after the deploy") ]
  end

  test "keeps confident lessons, at most three, each about a name it was given or nothing" do
    stub_model(lessons: [
      { fact: "Checkout keeps sessions in firefight-prod", about: "checkout", confidence: 0.9 },
      { fact: "A guess", about: "", confidence: 0.3 },
      { fact: "Web pools 5 connections", about: "somewhere else", confidence: 0.8 },
      { fact: "Three", about: "", confidence: 0.9 }, { fact: "Four", about: "", confidence: 0.9 }
    ])

    lessons = @extractor.extract(@incident, sources: @sources, subjects: [ "Checkout" ]).lessons

    assert_equal [ "Checkout keeps sessions in firefight-prod", "Web pools 5 connections", "Three" ], lessons.map(&:fact)
    assert_equal [ "Checkout", nil, nil ], lessons.map(&:about)
  end

  test "reads verdicts only on lessons it was shown, and no sources means no call" do
    stub_model(verdicts: [
      { memory_id: "m1", verdict: "contradicts", correction: "It is firefight-dev" },
      { memory_id: "m2", verdict: "agrees", correction: "" },
      { memory_id: "unknown", verdict: "agrees", correction: "" }
    ])
    known = [ FirefightAi::LessonExtractor::Known.new(id: "m1", text: "a"), FirefightAi::LessonExtractor::Known.new(id: "m2", text: "b") ]

    verdicts = @extractor.extract(@incident, sources: @sources, known: known).verdicts

    assert_equal [ [ "m1", "contradicts", "It is firefight-dev" ], [ "m2", "agrees", nil ] ], verdicts.map { |each| [ each.memory_id, each.verdict, each.correction ] }
    RubyLLM.expects(:chat).never
    assert_empty @extractor.extract(@incident, sources: [ FirefightAi::LessonExtractor::Source.new(title: "Empty", text: "") ]).lessons
  end

  test "is shown what the workspace already remembers, rejected ones marked, so it never learns them again" do
    chat = stub_model
    asked = nil
    chat.stubs(:ask).with { |prompt| (asked = prompt) || true }.returns(llm_reply(content: { "lessons" => [], "verdicts" => [] }, input: 100, output: 50, cost: 0.0001))
    remembered = [
      FirefightAi::LessonExtractor::Remembered.new(text: "Checkout keeps sessions in Redis", rejected: false),
      FirefightAi::LessonExtractor::Remembered.new(text: "Checkout uses MySQL", rejected: true)
    ]

    @extractor.extract(@incident, sources: @sources, remembered: remembered)

    assert_includes asked, "Already remembered in this workspace:\n- Checkout keeps sessions in Redis\n- Checkout uses MySQL (rejected)"
  end

  private

  def stub_model(lessons: [], verdicts: [])
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).returns(llm_reply(content: { "lessons" => lessons, "verdicts" => verdicts }, input: 100, output: 50, cost: 0.0001))
    RubyLLM.stubs(:chat).returns(chat)
    chat
  end
end
