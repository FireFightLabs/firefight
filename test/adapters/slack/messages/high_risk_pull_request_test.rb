require "test_helper"

class Slack::Messages::HighRiskPullRequestTest < ActiveSupport::TestCase
  Shown = PullRequestReviewAlertService::Shown
  Finding = PullRequestReviewAlertService::ShownFinding

  test "the title names the repository, the body links the pull request and quotes why it is risky, and the footer says how to turn it off" do
    blocks = build

    assert_equal ":octagonal_sign:  *High risk pull request in acme/auth*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_equal "*<https://github.com/acme/auth/pull/7|#7 Change the payment timeout>*\n> Checkout retries rise with the timeout.", blocks.third.dig(:text, :text)
    assert_includes blocks.find { |block| block[:type] == "context" }.dig(:elements, 0, :text), "Turn this off on Auth Service in the catalog"
    button = blocks.last[:elements].sole
    assert_equal [ "Open pull request", "https://github.com/acme/auth/pull/7", Identifiers::OPEN_PULL_REQUEST ], [ button.dig(:text, :text), button[:url], button[:action_id] ]
  end

  test "open findings are listed with the lesson behind each, three at most, and what came from a model or the host is escaped" do
    findings = [ Finding.new(severity: "Critical", claim: "Raises the <!channel> timeout", lesson: "Lesson from INC-052") ] +
               Array.new(3) { |index| Finding.new(severity: "Minor", claim: "Small #{index}", lesson: nil) }
    blocks = build(findings: findings, title: "<b>Timeout</b>")

    listed = blocks.fourth.dig(:text, :text)
    assert_includes listed, "• *Critical*  Raises the &lt;!channel&gt; timeout  ·  _Lesson from INC-052_"
    assert listed.end_with?("and 1 more on the pull request")
    assert_includes blocks.third.dig(:text, :text), "&lt;b&gt;Timeout&lt;/b&gt;"
  end

  private

  def shown(findings: [], title: "Change the payment timeout")
    Shown.new(repository: "acme/auth", number: 7, title: title, url: "https://github.com/acme/auth/pull/7",
              risk_reason: "Checkout retries rise with the timeout.", service: "Auth Service", findings: findings)
  end

  def build(**) = Slack::Messages::HighRiskPullRequest.build(shown(**))
end
