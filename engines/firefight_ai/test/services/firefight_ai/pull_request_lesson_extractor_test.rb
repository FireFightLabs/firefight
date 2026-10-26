require "test_helper"

class FirefightAi::PullRequestLessonExtractorTest < ActiveSupport::TestCase
  Extractor = FirefightAi::PullRequestLessonExtractor
  Schema = FirefightAi::Schemas::PullRequestLesson

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @extractor = Extractor.new(@workspace)
    @handled = Extractor::Handled.new(kind: Extractor::EDITED, person: "ada", words: "Commit by ada: Add the index concurrently", changes: "+algorithm: :concurrently")
  end

  test "a confident lesson on a stated reason is kept, and the person's words reach the model framed as theirs" do
    chat = stub_model(lesson: "Migrations here add indexes concurrently", basis: Schema::STATED, confidence: 0.9)
    chat.expects(:ask).with { |text| text.include?("ada changed it before merging.") && text.include?("trust=\"untrusted\">\nCommit by ada") }
        .returns(reply(lesson: "Migrations here add indexes concurrently", basis: Schema::STATED, confidence: 0.9))

    result = extract

    assert_equal [ "Migrations here add indexes concurrently", Schema::STATED ], [ result.lesson, result.basis ]
  end

  test "no basis, a guess, or a repeat with nothing earlier to repeat is no lesson" do
    stub_model(lesson: "Something", basis: Schema::NONE, confidence: 0.9)
    assert_nil extract
    stub_model(lesson: "Something", basis: Schema::STATED, confidence: 0.4)
    assert_nil extract
    stub_model(lesson: "Something", basis: Schema::REPEATED, confidence: 0.9)
    assert_nil extract
    assert extract(earlier: [ Extractor::Earlier.new(label: "PR #3", kind: Extractor::EDITED, summary: "Made the index concurrent") ])
  end

  private

  def extract(earlier: []) = @extractor.extract(inferable: nil, repository: "acme/api", label: "PR #12", title: "Add an index", handled: @handled, earlier: earlier)

  def reply(**content) = llm_reply(content: content.stringify_keys, input: 100, output: 20, cost: 0.0001)

  def stub_model(**content)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).returns(reply(**content))
    RubyLLM.stubs(:chat).returns(chat)
    chat
  end
end
