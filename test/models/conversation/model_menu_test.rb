require "test_helper"

class Conversation::ModelMenuTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "an OpenRouter account offers its main model first, then the listed models the registry can bill, cheapest first" do
    account = add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    menu = Conversation::ModelMenu.for(@workspace)

    assert_equal [ "openai/shared-vision", "z-ai/glm-5.2", "anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5" ], menu.models.map(&:model)
    main, glm, _sonnet, opus = menu.models
    assert main.default
    assert_equal [ "Shared Vision", Conversation::ModelMenu::DEFAULT_NOTE ], [ main.label, main.note ]
    assert_equal [ "GLM-5.2", "Fast and low cost for everyday questions" ], [ glm.label, glm.note ]
    assert_equal [ "Claude Opus 5.5", "Strongest, slower and pricier" ], [ opus.label, opus.note ]
    assert_not glm.reads_images
    assert menu.offers_choice?

    picked = menu.choice("z-ai/glm-5.2")
    assert_equal [ "z-ai/glm-5.2", "openrouter" ], [ picked.model, picked.provider ]
    assert_equal account, picked.payer.account, "a pick is paid for by the same account"
    assert picked.context, "and runs in that account's own context"
  end

  test "a listed main model is not offered twice, and picking it is no pick at all" do
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own", models: { "main" => "anthropic/claude-opus-5.5", "fast" => "openai/shared-vision" })
    menu = Conversation::ModelMenu.for(@workspace)

    assert_equal [ "z-ai/glm-5.2", "anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5" ], menu.models.map(&:model)
    assert_equal [ false, false, true ], menu.models.map(&:default)
    assert_nil menu.choice("anthropic/claude-opus-5.5")
  end

  test "a model not on the menu is refused, and a chat holding one runs on the main model" do
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    menu = Conversation::ModelMenu.for(@workspace)

    assert_equal Conversation::ModelMenu::NOT_OFFERED, menu.blocked_reason("deepseek/deepseek-v4-pro"), "listed, but the registry does not hold it"
    assert_nil menu.blocked_reason("z-ai/glm-5.2")
    assert_nil menu.choice("gpt-4o")
    assert_equal "openai/shared-vision", menu.current("gpt-4o")
  end

  test "the house's keys offer the listed models only for a provider the deployment holds a key for" do
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("INVESTIGATION_AI_MODEL").returns("anthropic/claude-opus-5.5")
    ENV.stubs(:[]).with("INVESTIGATION_AI_PROVIDER").returns("openrouter")
    assert_not Conversation::ModelMenu.for(@workspace).offers_choice?, "no OpenRouter key here"

    keyed = RubyLLM.config.dup
    keyed.openrouter_api_key = "sk-or-deployment"
    RubyLLM.stubs(:config).returns(keyed)
    menu = Conversation::ModelMenu.for(@workspace)

    assert_equal [ "z-ai/glm-5.2", "anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5" ], menu.models.map(&:model)
    picked = menu.choice("z-ai/glm-5.2")
    assert_equal Inference::PAID_BY_OPERATOR, picked.payer.paid_by
    assert_nil picked.context
  end

  test "a workspace on Firefight's credits picks from the same models, paid with its credits" do
    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(true, false))
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("INVESTIGATION_AI_MODEL").returns("anthropic/claude-opus-5.5")
    ENV.stubs(:[]).with("INVESTIGATION_AI_PROVIDER").returns("openrouter")
    keyed = RubyLLM.config.dup
    keyed.openrouter_api_key = "sk-or-deployment"
    RubyLLM.stubs(:config).returns(keyed)

    assert_equal Inference::PAID_BY_CREDITS, Conversation::ModelMenu.for(@workspace).choice("z-ai/glm-5.2").payer.paid_by
  end

  test "nothing is offered when nobody can pay" do
    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(false, true))

    assert_empty Conversation::ModelMenu.for(@workspace).models
  end

  test "a reply names its model by the picker's name, else the registry's, else its id" do
    assert_equal "GLM-5.2", Conversation::ModelMenu.label("z-ai/glm-5.2", provider: "openrouter")
    assert_equal "Claude Sonnet 4.5", Conversation::ModelMenu.label("claude-sonnet-4-5", provider: "anthropic")
    assert_equal "mystery-model", Conversation::ModelMenu.label("mystery-model", provider: "openrouter")
  end
end
