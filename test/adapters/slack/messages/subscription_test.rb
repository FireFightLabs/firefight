require "test_helper"

class Slack::Messages::SubscriptionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @incident.update!(channel_id: "C_SUB_TEST")
  end

  test "a subscribe confirmation carries Unsubscribe, and an unsubscribe confirmation carries Subscribe" do
    subscribed = Slack::Messages::Subscription.notice(@incident, Incident::Subscriptions::SUBSCRIBED)
    already = Slack::Messages::Subscription.notice(@incident, Incident::Subscriptions::ALREADY_SUBSCRIBED)
    unsubscribed = Slack::Messages::Subscription.notice(@incident, Incident::Subscriptions::UNSUBSCRIBED)

    assert_equal [ Identifiers::UNSUBSCRIBE_INCIDENT ], action_ids(subscribed)
    assert_equal [ Identifiers::UNSUBSCRIBE_INCIDENT ], action_ids(already)
    assert_equal [ Identifiers::SUBSCRIBE_INCIDENT ], action_ids(unsubscribed)
    assert_equal @incident.subscription_notice(Incident::Subscriptions::SUBSCRIBED), subscribed.first[:text][:text]
    assert_equal @incident.id, buttons(unsubscribed).first[:value]
  end

  test "a subscriber's update names the incident and its channel on top, keeps the reply intact, and offers the ways out below" do
    reply = [ { type: "section", text: { type: "mrkdwn", text: "Severity went up" } } ]

    blocks = Slack::Messages::Subscription.wrap_update(@incident, reply, homepage_url: "https://app.example.com/incidents/1")

    assert_equal "#{Slack::Emoji::DECLARED} *#{@incident.identifier} · #{@incident.name}* in <#C_SUB_TEST>", blocks.first.dig(:text, :text)
    assert_equal %w[section divider section divider actions], blocks.pluck(:type)
    assert_equal reply.first, blocks.third
    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::INCIDENT_HOMEPAGE, Identifiers::UNSUBSCRIBE_INCIDENT ], action_ids(blocks)
    assert_equal [ "Open channel", "Open in Firefight", "#{Slack::Emoji::UNSUBSCRIBE} Unsubscribe" ], buttons(blocks).map { |button| button.dig(:text, :text) }
    open_channel = buttons(blocks).first
    assert_includes open_channel[:url], "C_SUB_TEST"
    assert_includes open_channel[:url], @workspace.platform_id
  end

  test "without a dashboard host the homepage button is left out rather than dead" do
    blocks = Slack::Messages::Subscription.wrap_update(@incident, [], homepage_url: nil)

    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::UNSUBSCRIBE_INCIDENT ], action_ids(blocks)
  end

  private

  def buttons(blocks)
    blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }
  end

  def action_ids(blocks)
    buttons(blocks).map { |button| button[:action_id] }
  end
end
