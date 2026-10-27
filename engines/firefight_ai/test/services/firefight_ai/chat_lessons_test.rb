require "test_helper"

class FirefightAi::ChatLessonsTest < ActiveSupport::TestCase
  setup do
    @lessons = FirefightAi::ChatLessons.new(workspaces(:slack_workspace_one))
  end

  test "lasting facts the chat showed come back, at most three and only those it is sure of, with what is already remembered handed over" do
    chat = stub_model(content: { lessons: [
      { fact: "web deploys from the release branch", about: "web", confidence: 0.9 },
      { fact: "Checkout might use Redis", about: "", confidence: 0.4 },
      { fact: "Sessions live in firefight-prod", about: "", confidence: 0.8 },
      { fact: "The worker restarts nightly", about: "worker", confidence: 0.75 },
      { fact: "Backups run at night", about: "", confidence: 0.95 }
    ] })
    chat.expects(:ask).with { |text| text.include?("- Checkout uses MySQL (rejected)") && text.include?("## The chat (chronological)\nAna: where does web deploy from?") }
        .returns(llm_reply(content: { lessons: [
          { fact: "web deploys from the release branch", about: "web", confidence: 0.9 }, { fact: "Checkout might use Redis", about: "", confidence: 0.4 },
          { fact: "Sessions live in firefight-prod", about: "", confidence: 0.8 }, { fact: "The worker restarts nightly", about: "worker", confidence: 0.75 }
        ] }, input: 100, output: 20, cost: 0.0001))

    found = @lessons.extract(transcript: "Ana: where does web deploy from?\nHalon: The deploy settings name the release branch.",
                             remembered: [ FirefightAi::ChatLessons::Remembered.new(text: "Checkout uses MySQL", rejected: true) ])

    assert_equal [ [ "web deploys from the release branch", "web" ], [ "Sessions live in firefight-prod", nil ], [ "The worker restarts nightly", "worker" ] ],
                 found.map { |lesson| [ lesson.fact, lesson.about ] }
    assert Inference.exists?(feature: FirefightAi::ChatLessons::FEATURE)
  end

  test "an empty chat asks no model, and a model that fails is raised as a FirefightAi error" do
    RubyLLM.expects(:chat).never
    assert_empty @lessons.extract(transcript: "")

    RubyLLM.unstub(:chat)
    chat = stub_model(content: {})
    chat.stubs(:ask).raises(RubyLLM::Error.new("the provider failed"))
    assert_raises(FirefightAi::Error) { @lessons.extract(transcript: "Ana: hi") }
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
