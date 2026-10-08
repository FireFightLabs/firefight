require "test_helper"

class FirefightAi::QuestionAnswererTest < ActiveSupport::TestCase
  setup do
    @answerer = FirefightAi::QuestionAnswerer.new(workspaces(:slack_workspace_one))
  end

  test "Halon answers only what the material settles, and leaves the rest to the person" do
    stub_model(content: { answered: true, answer: "The tag, as the person said in their second message.", option: "" })
    assert_equal FirefightAi::QuestionAnswerer::Reply.new(text: "The tag, as the person said in their second message.", option: nil),
                 @answerer.answer(question: "Tag or commit?", known: "The person: send the tag")

    stub_model(content: { answered: true, answer: "Email and Google sign-in already link by verified email.", option: "link by email" })
    reply = @answerer.answer(question: "Link Slack by email?", known: "", options: [ [ "Link by email", "Accounts merge" ], [ "Keep apart", "Two accounts" ] ],
                             recommended: "Keep apart, simpler")
    assert_equal "Link by email", reply.option, "an option is picked by its label, whichever was recommended"

    stub_model(content: { answered: false, answer: "" })
    assert_nil @answerer.answer(question: "Which region?", known: "")
  end

  private

  def stub_model(content:)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    reply = llm_reply(content: content, input: 100, output: 20, cost: 0.0001)
    reply.stubs(:parsed).returns(content.deep_stringify_keys)
    chat.stubs(:ask).returns(reply)
    RubyLLM.stubs(:chat).returns(chat)
  end
end
