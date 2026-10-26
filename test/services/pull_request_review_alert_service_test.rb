require "test_helper"

class PullRequestReviewAlertServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    catalog_types(:service_ws1).catalog_attribute_definitions.create!(name: "Code", slug: "code", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
                                                                      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9)
    @service = catalog_entries(:auth_service)
    @service.update!(attributes: @service.entry_attributes.merge("code" => "acme/auth", "slack_channel" => "C-AUTH"))
    @review = review!
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
  end

  test "a high risk review is posted once in the owning service's channel, with its open findings most severe first" do
    minor = finding("Logs the token", severity: PullRequestReview::Finding::SEVERITY_MINOR)
    finding("Raises the payment timeout", severity: PullRequestReview::Finding::SEVERITY_CRITICAL)
    minor.fixed!("b" * 40)
    finding("Drops a column still read", severity: PullRequestReview::Finding::SEVERITY_MAJOR)
    @adapter.expects(:post_high_risk_pull_request).once.with { |channel_id:, alert:|
      channel_id == "C-AUTH" && alert.service == "Auth Service" && alert.findings.map(&:claim) == [ "Raises the payment timeout", "Drops a column still read" ]
    }.returns(message_id: "1.1", channel_id: "C-AUTH")

    assert_equal [ "C-AUTH" ], service.post!
    assert_empty service.post!
  end

  test "a review again of the same pull request is not posted twice" do
    @adapter.stubs(:post_high_risk_pull_request).returns(message_id: "1.1", channel_id: "C-AUTH")
    service.post!
    again = review!(head_sha: "c" * 40)
    @adapter.expects(:post_high_risk_pull_request).never

    assert_empty PullRequestReviewAlertService.new(again).post!
  end

  test "nothing is posted below high risk, for a service that turned it off, or for a rehearsal" do
    @adapter.expects(:post_high_risk_pull_request).never

    @review.update!(risk: PullRequestReview::RISK_MEDIUM)
    assert_empty service.post!
    @review.update!(risk: PullRequestReview::RISK_HIGH, rehearsal: true)
    assert_empty service.post!
    @review.update!(rehearsal: false)
    @service.update!(review_alerts: false)
    assert_empty service.post!
  end

  test "a channel that cannot take it is skipped" do
    @adapter.stubs(:post_high_risk_pull_request).raises(AdapterError::NotInChannel)

    assert_empty service.post!
  end

  test "a channel Slack asks to try later is tried again by the job, and one posted in already is never posted in twice" do
    @workspace.catalog_entries.create!(catalog_type: @service.catalog_type, name: "Payments", slug: "payments",
                                       attributes: { "code" => "acme/auth", "slack_channel" => "C-PAY" })
    @adapter.expects(:post_high_risk_pull_request).with { |channel_id:, **| channel_id == "C-AUTH" }.once.returns(message_id: "1", channel_id: "C-AUTH")
    @adapter.expects(:post_high_risk_pull_request).with { |channel_id:, **| channel_id == "C-PAY" }.twice
            .raises(AdapterError::RateLimited.new(1)).then.returns(message_id: "2", channel_id: "C-PAY")

    assert_raises(PullRequestReviewAlertService::Retry) { service.post! }
    assert_equal [ "C-PAY" ], service.post!
    assert_equal %w[C-AUTH C-PAY], @review.reload.high_risk_posted_channels
  end

  test "a review that finished is posted from a job" do
    running = review!(number: 11, status: PullRequestReview::STATUS_RUNNING)

    assert_enqueued_with(job: PullRequestReviewAlertJob, args: [ running.id ]) { running.finish!(status: PullRequestReview::STATUS_DONE) }
  end

  private

  def service = PullRequestReviewAlertService.new(@review.reload)

  def review!(number: 7, head_sha: "a" * 40, status: PullRequestReview::STATUS_DONE)
    PullRequestReview.create!(workspace: @workspace, repository: "acme/auth", number: number, head_sha: head_sha, title: "Change the payment timeout",
                              url: "https://github.com/acme/auth/pull/#{number}", trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400,
                              status: status, risk: PullRequestReview::RISK_HIGH, risk_reason: "Checkout retries rise with the timeout.")
  end

  def finding(claim, severity:)
    @review.findings.create!(
      position: @review.next_position, fingerprint: SecureRandom.hex(16), category: PullRequestReview::Finding::CATEGORY_STABILITY,
      severity: severity, effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: claim, why: "Because.", path: "app/a.rb", line: 3
    )
  end
end
