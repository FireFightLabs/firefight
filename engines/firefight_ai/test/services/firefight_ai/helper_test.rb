require "test_helper"

class FirefightAi::HelperTest < ActiveSupport::TestCase
  setup do
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    @choice = FirefightAi::ModelChoice.new(model: "gpt-4o-mini")
  end

  test "a helper only reads, stays inside its brief and reports in a few lines that cite the steps, written like Firefight's copy" do
    prompt = FirefightAi::Helper.template_text

    assert_includes prompt, "Only read. Never change anything"
    assert_includes prompt, "Stay inside the brief."
    assert_includes prompt, "at most five short lines"
    assert_includes prompt, "end each finding with the steps it rests on"
    assert_includes prompt, FirefightAi::Evidence::RULE
    assert_includes prompt, FirefightAi::Copy::RULE
  end

  test "the chat and the run are told when to hand reads to helpers" do
    assert_includes FirefightAi::Investigator.system_prompt, FirefightAi::Helper::RULE
    assert_includes FirefightAi::Responder.new(@workspace, inferable: nil).send(:template_text), FirefightAi::Helper::RULE
  end

  test "it runs one loop on the model it was given, whose plain reply is its report, within a few turns and its share of the budget" do
    chat = mock("chat")
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.expects(:with_instructions).with(FirefightAi::Helper.template_text)
    FirefightAi::AgentLoop.expects(:new).with do |**given|
      given[:reply_is_answer] && given[:choice] == @choice && given[:purpose] == AiPurpose::HELPER &&
        given[:budget].max_turns == FirefightAi::Helper::MAX_TURNS && given[:budget].max_spend_cents == 25 &&
        given[:inference][:feature] == FirefightAi::Helper::FEATURE && given[:inference][:model] == "gpt-4o-mini"
    end.returns(stub(run: :outcome))

    outcome = FirefightAi::Helper.new(@workspace, inferable: nil, choice: @choice, purpose: AiPurpose::HELPER)
                                 .run(chat: chat, tools: [], max_spend_cents: 25, canceled: -> { false })

    assert_equal :outcome, outcome
  end
end
