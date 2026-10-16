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

  test "a subscriber's update is one short card naming the incident, what happened and the words, with the ways out" do
    blocks = digest(rich: true)
    card = blocks.sole

    assert_equal "card", card[:type]
    assert_equal "#{Slack::Emoji::RESOLVED} #{@incident.identifier} · #{@incident.name}", card.dig(:title, :text)
    assert_equal "Resolved by <@U1> after 5m", card.dig(:subtitle, :text)
    assert_equal "Rolled back the deploy", card.dig(:body, :text)
    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::INCIDENT_HOMEPAGE, Identifiers::UNSUBSCRIBE_INCIDENT ], card[:actions].pluck(:action_id)
    assert_includes card[:actions].first[:url], "C_SUB_TEST"
    assert_includes card[:actions].first[:url], @workspace.platform_id
  end

  test "a subscriber's card reads the same as plain blocks where cards are not drawn" do
    blocks = digest(rich: false)

    assert_equal %w[section context divider section actions], blocks.pluck(:type)
    assert_equal "> Rolled back the deploy", blocks.fourth.dig(:text, :text)
  end

  test "without a dashboard host the homepage button is left out rather than dead" do
    blocks = Slack::Messages::Subscription.digest(@incident, headline: "Updated", body: nil, icon: Slack::Emoji::UPDATED, homepage_url: nil, rich: false)

    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::UNSUBSCRIBE_INCIDENT ], action_ids(blocks)
  end

  private

  def digest(rich:)
    Slack::Messages::Subscription.digest(@incident, headline: "Resolved by <@U1> after 5m", body: "Rolled back the deploy", icon: Slack::Emoji::RESOLVED,
                                                    homepage_url: "https://app.example.com/incidents/1", rich: rich)
  end

  def buttons(blocks)
    blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }
  end

  def action_ids(blocks)
    buttons(blocks).map { |button| button[:action_id] }
  end
end
