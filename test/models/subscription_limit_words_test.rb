require "test_helper"

class SubscriptionLimitWordsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    subscription_proxy_up!
    @limit = FirefightAi::TransientError.new("All credentials for model are cooling down", reason: "RateLimitError")
  end

  test "a subscription at its limit is said plainly, with when it resets" do
    add_subscription_account!(@workspace, state: { "limit" => { "reached_until" => 2.hours.from_now.iso8601 } })

    assert_equal "Halon cannot answer right now because this workspace's ChatGPT subscription reached its usage limit. It resets in about 2 hours. " \
                 "An admin can see it under Settings, Workspace, AI accounts.", AiCredit.subscription_limit(@workspace)
  end

  test "a workspace whose first account is not a subscription is told what it was told before" do
    assert_nil AiCredit.subscription_limit(@workspace)
  end

  test "a switch away from a subscription at its limit says so, by the model's own name" do
    account = add_subscription_account!(@workspace)
    assert SubscriptionProxy.limit_reached?(account.choice_for(AiPurpose::INVESTIGATION), @limit)
    assert_not SubscriptionProxy.limit_reached?(FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"), @limit)

    switch = Chat::ModelSwitch.new(failed_model: "#{@workspace.id}/gpt-6.1-sol", failed_provider: AiProviders::SUBSCRIPTION_PROXY,
                                   backup_model: "claude-haiku-4-5", backup_provider: "anthropic", cause: Chat::ModelSwitch::CAUSE_LIMIT_REACHED)
    switch.stubs(:chat).returns(stub(owner: Object.new))

    assert_match "This workspace's subscription reached its usage limit for GPT 6.1 Sol, so I switched to", switch.shown_as
  end

  test "a reply that gave up on a subscription's limit says so in the chat" do
    add_subscription_account!(@workspace, state: { "limit" => { "reached_until" => 30.minutes.from_now.iso8601 } })
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    said = nil
    Conversation::Delivery.stubs(:give_up!).with { |_conversation, text| said = text }

    ConversationReplyJob.say_nothing_came_of_it(ConversationReplyJob.new(conversation.id), @limit)

    assert_match "ChatGPT subscription reached its usage limit. It resets in about 30 minutes.", said
  end
end
