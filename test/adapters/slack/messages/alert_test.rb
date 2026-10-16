require "test_helper"

class Slack::Messages::AlertTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @source = AlertSource.create!(workspace: @workspace, name: "Sentry", provider: AlertSource::PROVIDER_SENTRY)
  end

  def alert_with(fields)
    @source.alerts.new(workspace: @workspace, fields: fields, received_at: Time.current, last_seen_at: Time.current)
  end

  def title_text(alert) = Slack::Messages::Alert.build(alert).first.dig(:text, :text)

  test "the title links to the alert's page in the tool that sent it" do
    alert = alert_with("title" => "ReferenceError <b>", "url" => "https://sentry.io/organizations/acme/issues/1/?a=b|c")

    assert_equal "#{Slack::Emoji::ALERT_FIRING}  *<https://sentry.io/organizations/acme/issues/1/?a=bc|ReferenceError &lt;b&gt;>*", title_text(alert)
  end

  test "a title without a link stays plain" do
    assert_equal "#{Slack::Emoji::ALERT_FIRING}  *Disk full*", title_text(alert_with("title" => "Disk full"))
  end

  test "a firing alert has an emoji of its own, never the one an incident is declared with, and no pipes" do
    blocks = Slack::Messages::Alert.build(alert_with("title" => "Disk full"))

    assert_not_equal Slack::Emoji::DECLARED, Slack::Emoji::ALERT_FIRING
    assert_not blocks.to_s.include?("|")
  end
end
