require "test_helper"

class FirefightAi::AnswerJudgeTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @judge = FirefightAi::AnswerJudge.new(@workspace, inferable: nil)
  end

  test "reads the verdict and its reason, and anything it does not recognise is unclear" do
    stub_model(verdict: "same", reason: "Both blame the full disk.")
    assert_equal [ "same", "Both blame the full disk." ], verdict_of(@judge.judge(rated: "Disk full", replayed: "The disk filled"))

    stub_model(verdict: "maybe", reason: "")
    assert_equal FirefightAi::Schemas::SameCause::UNCLEAR, @judge.judge(rated: "Disk full", replayed: "No idea").verdict
  end

  test "grades on Firefight's own model, never a workspace's override" do
    FirefightAi.expects(:model_for).with(AiPurpose::CITATION_CHECK).returns(FirefightAi::ModelChoice.new(model: "gpt-5.6-luna", provider: "openai"))
    stub_model(verdict: "different", reason: "Disk against deploy.")

    assert_equal "different", @judge.judge(rated: "Disk full", replayed: "The deploy").verdict
  end

  private

  def verdict_of(said) = [ said.verdict, said.reason ]

  def stub_model(content)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).returns(llm_reply(content: content, input: 100, output: 20, cost: 0.0001))
    RubyLLM.stubs(:chat).returns(chat)
  end
end
