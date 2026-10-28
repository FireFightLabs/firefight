require "test_helper"

class WorkspaceAiAccountSubscriptionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    subscription_proxy_up!
  end

  test "a subscription calls the proxy with only its client key, naming its model with the workspace's prefix" do
    account = add_subscription_account!(@workspace)

    choice = account.choice_for(AiPurpose::INVESTIGATION)

    assert_equal "#{@workspace.id}/gpt-6.1-sol", choice.model
    assert_equal AiProviders::SUBSCRIPTION_PROXY, choice.provider
    config = choice.context.config
    assert_equal [ "client-key", "#{SubscriptionProxyHelper::PROXY_URL}/v1" ], [ config.subscription_proxy_api_key, config.subscription_proxy_api_base ]
    others = AiProviders.every_provider_option - %i[subscription_proxy_api_key subscription_proxy_api_base]
    assert others.all? { |option| config.public_send(option).nil? }, "no other provider's setting reaches a subscription's call"
    assert_equal "#{@workspace.id}/gpt-6-luna", account.choice_for(AiPurpose::SUMMARY).model
  end

  test "its recommended models are the first the sign-in serves, and an admin may pick only one it serves" do
    account = add_subscription_account!(@workspace, models: [ SubscriptionProxyHelper::SUBSCRIPTION_MODELS.last ])
    assert_equal "gpt-6-luna", account.model_for(WorkspaceAiAccount::MAIN), "the first it serves when none recommended is there"

    account.assign_models(main: "gpt-4o")
    assert_not account.valid?
    assert_includes account.errors[:"models.main"], "is not a model this subscription serves"
  end

  test "the engine reads a subscription model's size from what the proxy listed, for this workspace only" do
    add_subscription_account!(@workspace)
    other = workspaces(:slack_workspace_two)

    assert_equal 272_000, FirefightAi.context_window("#{@workspace.id}/gpt-6.1-sol", provider: AiProviders::SUBSCRIPTION_PROXY)
    assert_equal "GPT 6.1 Sol", FirefightAi.model_name("#{@workspace.id}/gpt-6.1-sol", provider: AiProviders::SUBSCRIPTION_PROXY)
    assert_nil FirefightAi.context_window("#{other.id}/gpt-6.1-sol", provider: AiProviders::SUBSCRIPTION_PROXY)
    assert_nil FirefightAi.context_window("gpt-6.1-sol", provider: AiProviders::SUBSCRIPTION_PROXY)
  end

  test "Halon pays with a subscription only while the proxy is usable, and one subscription's sign-ins are one pool" do
    first = add_subscription_account!(@workspace, credential: "codex-a.json")
    add_subscription_account!(@workspace, credential: "codex-b.json", email: "ben@example.com")

    pooled = AiFunding.for(@workspace, AiPurpose::INVESTIGATION).select(&:own_account?)
    assert_equal [ first ], pooled.map { |choice| choice.payer.account }

    SubscriptionProxy::Check.failed!("could not reach the subscription proxy")
    @workspace.forget_held_read(:usable_ai_accounts)
    assert_empty AiFunding.for(@workspace, AiPurpose::INVESTIGATION).select(&:own_account?)
  end

  test "one subscription at its limit hands a run to another subscription, which a provider being down would not" do
    chatgpt = add_subscription_account!(@workspace, credential: "codex-a.json")
    grok = add_subscription_account!(@workspace, subscription: "supergrok", credential: "xai-a.json",
                                                 models: [ { "id" => "grok-4.7", "name" => "Grok 4.7", "context_window" => 500_000 } ])
    failing = chatgpt.choice_for(AiPurpose::INVESTIGATION)

    backup = AiFunding.backup_for(@workspace, AiPurpose::INVESTIGATION, failing: failing)

    assert_equal grok, backup.payer.account
  end

  test "its state says when its sign-in stopped working or it reached its limit, and its toasts name it" do
    signed_out = add_subscription_account!(@workspace, state: { "signed_out" => true })
    limited = add_subscription_account!(@workspace, email: "ben@example.com", state: { "limit" => { "reached_until" => 2.hours.from_now.iso8601 } })

    assert_equal [ :signed_out, :limit_reached ], [ signed_out.state, limited.state ]
    assert_equal "ChatGPT subscription for ben@example.com", limited.subscription_named
    assert WorkspaceAiAccount.usable.exists?(limited.id), "a limit changes nothing about which accounts Halon tries"
  end
end
