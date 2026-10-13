require "test_helper"

class AiFundingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "the workspace's own accounts come first by position, skipping any switched off, out of credit or refused, then the operator's keys" do
    first = add_ai_account!(@workspace, label: "First")
    off = add_ai_account!(@workspace, label: "Off", enabled: false)
    dry = add_ai_account!(@workspace, label: "Dry", out_of_credit_since: 1.hour.ago)
    refused = add_ai_account!(@workspace, label: "Refused", failing_since: 1.hour.ago)
    second = add_ai_account!(@workspace, provider: "openai", key: "sk-own-openai", label: "Second")

    choices = AiFunding.for(@workspace, AiPurpose::INVESTIGATION)

    assert_equal [ first, second, nil ], choices.map { |choice| choice.payer.account }
    assert_equal [ Inference::PAID_BY_ACCOUNT, Inference::PAID_BY_ACCOUNT, Inference::PAID_BY_OPERATOR ], choices.map { |choice| choice.payer.paid_by }
    assert_equal [ "claude-sonnet-4-5", "gpt-4o" ], choices.first(2).map(&:model)
    assert_nil choices.last.context, "the operator's keys run on the deployment's own configuration"
    assert_not_includes choices.filter_map { |choice| choice.payer.account }, off
    assert_not_includes choices.filter_map { |choice| choice.payer.account }, dry
    assert_not_includes choices.filter_map { |choice| choice.payer.account }, refused
  end

  test "an account's quick model runs summaries, milestones and mention replies, and its main model the rest" do
    add_ai_account!(@workspace)

    assert_equal "claude-haiku-4-5", FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).model
    assert_equal "claude-haiku-4-5", FirefightAi.model_for(AiPurpose::INCIDENT_RESPONSE, workspace: @workspace).model
    assert_equal "claude-sonnet-4-5", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model
    assert_equal "claude-sonnet-5-5", FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace).model, "code fixes are written on the model recommended for writing code"
    assert_equal "claude-opus-5-5", FirefightAi.model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model, "and reviewed on the one recommended for reviewing it"
  end

  test "code fixes are written on Claude Sonnet 5.5 and reviewed on Claude Opus 5.5 where an Anthropic or OpenRouter account reaches them, and on the next best model otherwise" do
    openai = add_ai_account!(@workspace, provider: "openai", key: "sk-own-openai", label: "OpenAI")
    assert_equal "gpt-4o", FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace).model, "an OpenAI account writes code with its main model"
    assert_equal "gpt-4o", FirefightAi.model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model, "and reviews it with the same"

    openai.destroy!
    router = add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own", label: "OpenRouter")
    main = router.model_for(WorkspaceAiAccount::MAIN)
    assert_equal [ "anthropic/claude-sonnet-5.5", "openrouter" ], FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace).to_h.values_at(:model, :provider)
    assert_equal [ "anthropic/claude-opus-5.5", "openrouter" ], FirefightAi.model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).to_h.values_at(:model, :provider)
    assert_equal main, FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).model, "no other purpose changes"

    FirefightAi.stubs(:priced_for?).returns(false)
    assert_equal main, FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace).model, "a model the registry cannot price is never a fix's"
    assert_equal main, FirefightAi.model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model
  end

  test "a change is reviewed on the review model of whoever paid for writing it" do
    own = add_ai_account!(@workspace)
    writing = FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace)

    reviewing = FirefightAi.review_choice_for(writing, workspace: @workspace)
    assert_equal [ "claude-opus-5-5", own ], [ reviewing.model, reviewing.payer.account ]

    house = FirefightAi.choices_for(AiPurpose::CODE_FIX, workspace: @workspace).last
    assert_nil FirefightAi.review_choice_for(house, workspace: @workspace).payer.account, "the house's writing is reviewed on the house's keys"

    nobody = writing.with(payer: AiPayer::NOBODY)
    assert_equal nobody, FirefightAi.review_choice_for(nobody, workspace: @workspace), "with no review model for that payer, the change's own"
  end

  test "the deployment's own keys write code fixes with Sonnet 5.5 and review them with Opus 5.5 when they reach them, unless a model is named for code fixes" do
    without = FirefightAi.deployment_model_for(AiPurpose::CODE_FIX, workspace: @workspace)
    assert_equal FirefightAi.deployment_model_for(AiPurpose::INVESTIGATION, workspace: @workspace).model, without.model, "no key reaches it, so the investigation's model"
    assert_equal without.model, FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model

    keyed = RubyLLM.config.dup
    keyed.anthropic_api_key = "sk-ant-deployment"
    RubyLLM.stubs(:config).returns(keyed)
    assert_equal [ "claude-sonnet-5-5", "anthropic" ], FirefightAi.deployment_model_for(AiPurpose::CODE_FIX, workspace: @workspace).to_h.values_at(:model, :provider)
    assert_equal [ "claude-opus-5-5", "anthropic" ], FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).to_h.values_at(:model, :provider)

    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("CODE_FIX_AI_MODEL").returns("gpt-4o")
    assert_equal "gpt-4o", FirefightAi.deployment_model_for(AiPurpose::CODE_FIX, workspace: @workspace).model
    assert_equal "gpt-4o", FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model, "a model named for code fixes still reviews them"

    ENV.stubs(:[]).with("CODE_REVIEW_AI_MODEL").returns("gpt-4.1")
    assert_equal "gpt-4.1", FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model
  end

  test "a workspace override for code fixes is its review's too until the review has one of its own" do
    keyed = RubyLLM.config.dup
    keyed.anthropic_api_key = "sk-ant-deployment"
    RubyLLM.stubs(:config).returns(keyed)
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::CODE_FIX, model: "claude-sonnet-4-5", provider: "anthropic")

    assert_equal "claude-sonnet-4-5", FirefightAi.deployment_model_for(AiPurpose::CODE_FIX, workspace: @workspace).model
    assert_equal "claude-sonnet-4-5", FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model

    @workspace.ai_model_overrides.create!(purpose: AiPurpose::CODE_REVIEW, model: "claude-opus-4-1", provider: "anthropic")
    assert_equal "claude-opus-4-1", FirefightAi.deployment_model_for(AiPurpose::CODE_REVIEW, workspace: @workspace).model
  end

  test "Firefight's own workspaces keep Firefight's key after their own accounts" do
    on_firefights_cloud!(own: true)

    assert_equal Inference::PAID_BY_FIREFIGHT, FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).payer.paid_by
  end

  test "on Firefight's cloud a workspace pays with its credits while they can pay, and with nothing after" do
    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(true, false))
    assert_equal Inference::PAID_BY_CREDITS, FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).payer.paid_by

    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(false, true))
    choice = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)
    assert choice.unpaid?, "nobody pays, so no call is made"
    assert_raises(FirefightAi::OutOfCredit) { FirefightAi.generate(choice, purpose: AiPurpose::SUMMARY, inference: { workspace: @workspace }) { flunk } }
  end

  test "embeddings stay on the deployment's model and account whoever pays for the rest" do
    add_ai_account!(@workspace)

    assert_equal FirefightAi.deployment_model_for(AiPurpose::EMBEDDING).model, FirefightAi.embedding_model
  end

  test "a rehearsal is Firefight measuring Halon, so it never runs on the workspace's own account" do
    add_ai_account!(@workspace)
    incident = incidents(:active_critical_ws1)
    rehearsal = @workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
                                                  max_turns: 4, max_spend_cents: 400)
    run = @workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400)

    assert_nil rehearsal.ai_model.payer, "the deployment's own account pays"
    assert_equal Inference::PAID_BY_ACCOUNT, run.ai_model.payer.paid_by
  end

  test "a model that stops answering on a workspace's own account carries on with that account's backup, then the next account on another provider, then the house" do
    first = add_ai_account!(@workspace, label: "First")
    add_ai_account!(@workspace, label: "Same provider")
    other = add_ai_account!(@workspace, provider: "openai", key: "sk-own-openai", label: "Other provider")
    failing = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    assert_equal first, failing.payer.account

    own = FirefightAi.backup_for(failing, purpose: AiPurpose::INVESTIGATION, workspace: @workspace)
    assert_equal [ "claude-haiku-5-5", first ], [ own.model, own.payer.account ], "the customer's own key first"

    following = FirefightAi.backup_for(own, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing ])
    assert_equal [ "gpt-4o", other ], [ following.model, following.payer.account ], "never another account on the provider that failed"

    with_backup("gpt-4o-mini", "openai") do
      house = FirefightAi.backup_for(following, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing, own ])
      assert_equal [ "gpt-4o-mini", Inference::PAID_BY_OPERATOR ], [ house.model, house.payer.paid_by ], "Firefight's own backup last"
    end
  end

  test "after the workspace's own accounts, the house carries on with the backup the deployment names, even on the same provider" do
    with_backup("claude-sonnet-4-5", "anthropic") do
      own = add_ai_account!(@workspace)
      failing = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
      account_backup = FirefightAi.backup_for(failing, purpose: AiPurpose::INVESTIGATION, workspace: @workspace)
      assert_equal own, account_backup.payer.account

      house = FirefightAi.backup_for(account_backup, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing ])
      assert_equal "gpt-4o", house.model, "the house's own model is on another provider, so it comes first"
      assert_equal Inference::PAID_BY_OPERATOR, house.payer.paid_by

      named = FirefightAi.backup_for(house, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing, account_backup ])
      assert_equal [ "claude-sonnet-4-5", "anthropic", Inference::PAID_BY_OPERATOR ], [ named.model, named.provider, named.payer.paid_by ]
      assert_not_equal own, named.payer.account

      assert_nil FirefightAi.backup_for(named, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing, account_backup, house ]),
                 "nothing is tried twice"
    end
  end

  test "with no backup named, the house carries on with the backup of another provider it holds a key for" do
    keyed = RubyLLM.config.dup
    keyed.anthropic_api_key = "sk-ant-deployment"
    keyed.openrouter_api_key = "sk-or-deployment"
    RubyLLM.stubs(:config).returns(keyed)
    failing = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    assert_equal [ "claude-sonnet-5-5", "anthropic" ], [ failing.model, failing.provider ]

    backup = FirefightAi.backup_for(failing, purpose: AiPurpose::INVESTIGATION, workspace: @workspace)

    assert_equal [ "anthropic/claude-haiku-5.5", "openrouter" ], [ backup.model, backup.provider ]
    assert_equal Inference::PAID_BY_OPERATOR, backup.payer.paid_by
  end

  test "on OpenRouter alone, the house carries on with Claude Haiku 5.5 on the same key when Claude Sonnet stops answering" do
    keyed = RubyLLM.config.dup
    keyed.openrouter_api_key = "sk-or-deployment"
    RubyLLM.stubs(:config).returns(keyed)
    failing = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    assert_equal [ "anthropic/claude-sonnet-5.5", "openrouter" ], [ failing.model, failing.provider ]
    assert_equal "anthropic/claude-haiku-5.5", FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).model, "side jobs run on Haiku too"
    assert_equal "anthropic/claude-haiku-5.5", FirefightAi.model_for(AiPurpose::HELPER, workspace: @workspace).model, "and so do helpers"

    backup = FirefightAi.backup_for(failing, purpose: AiPurpose::INVESTIGATION, workspace: @workspace)

    assert_equal [ "anthropic/claude-haiku-5.5", "openrouter", Inference::PAID_BY_OPERATOR ], [ backup.model, backup.provider, backup.payer.paid_by ]
    assert_nil FirefightAi.backup_for(backup, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing ]), "nothing is tried twice"
  end

  test "a house that cannot pay for the workspace is never its backup" do
    with_backup("gpt-4o-mini", "openai") do
      on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(false, true))
      add_ai_account!(@workspace)
      failing = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
      own = FirefightAi.backup_for(failing, purpose: AiPurpose::INVESTIGATION, workspace: @workspace)
      assert own.own_account?, "the account's own backup still carries on"

      assert_nil FirefightAi.backup_for(own, purpose: AiPurpose::INVESTIGATION, workspace: @workspace, tried: [ failing ])
    end
  end

  private

  def with_backup(model, provider)
    config = FirefightAi.configuration
    kept = [ config.backup_model, config.backup_provider ]
    config.backup_model = model
    config.backup_provider = provider
    yield
  ensure
    config.backup_model, config.backup_provider = kept
  end
end
