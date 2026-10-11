require "test_helper"

class FirefightAi::SpecialistTest < ActiveSupport::TestCase
  setup do
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    @choice = FirefightAi::ModelChoice.new(model: "gpt-4o-mini")
  end

  test "a specialist reads one kind of system, cites the lines and links it read and only proposes a change" do
    prompt = FirefightAi::Specialist.template_text

    assert_includes prompt, "End by calling report_findings once"
    assert_includes prompt, "the exact lines from the results that show it"
    assert_includes prompt, "You never make it yourself"
    assert_includes prompt, FirefightAi::Evidence::RULE
    assert_includes prompt, FirefightAi::Manual::THINKING
    assert_includes prompt, FirefightAi::Copy::WRITING
  end

  test "it runs one loop on the model it was given, with its kind's playbook, until its report is taken" do
    chat = mock("chat")
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.expects(:with_instructions).with("#{FirefightAi::Specialist.template_text}\nHow databases are read.", cache_until_here: true)
    answered = -> { true }
    FirefightAi::AgentLoop.expects(:new).with do |**given|
      given[:reply_is_answer] && given[:answered] == answered && given[:choice] == @choice && given[:purpose] == AiPurpose::HELPER &&
        given[:budget].max_turns == FirefightAi::Specialist::MAX_TURNS && given[:budget].max_spend_cents == 25 &&
        given[:inference][:feature] == FirefightAi::Specialist::FEATURE && given[:inference][:prompt_version] == FirefightAi::Specialist.prompt_version
    end.returns(stub(run: :outcome))

    outcome = FirefightAi::Specialist.new(@workspace, inferable: nil, choice: @choice, purpose: AiPurpose::HELPER)
                                     .run(chat: chat, tools: [], playbook: "How databases are read.", max_spend_cents: 25, canceled: -> { false }, answered: answered)

    assert_equal :outcome, outcome
  end

  test "the setting is auto by default, on or off overrides it, and anything else is refused at boot" do
    config = FirefightAi::Configuration.new

    assert_equal [ :auto, FirefightAi::Configuration::SPECIALIST_QUICK ], [ config.specialists, config.specialist_model ]
    config.specialists = "on"
    config.specialist_model = "main"
    assert_equal [ :on, true ], [ config.specialists, config.specialists_on_main? ]
    config.specialists = "OFF"
    assert_equal :off, config.specialists
    config.specialists = nil
    assert_equal :auto, config.specialists
    assert_raises(ArgumentError) { config.specialists = "sometimes" }
    assert_raises(ArgumentError) { config.specialist_model = "biggest" }
  end

  test "a chat's prompt says when reads go to specialists, so the two ways have different versions" do
    off = FirefightAi::Responder.new(@workspace, inferable: nil).prompt_version

    assert_not_equal off, FirefightAi::Responder.new(@workspace, inferable: nil, specialists: true).prompt_version
    assert_includes FirefightAi::Manual::TOOLS_WITH_SPECIALISTS, FirefightAi::Manual::SPECIALIST_READS
  end
end
