require "test_helper"

# What a review posts while another of its posts waits on an approval, and line comments a host would not say the ids of.
class PullRequestReviewCatchUpTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  REVIEW = Integrations::PullRequestReviews::REVIEW
  COMMENT = Integrations::PullRequestReviews::COMMENT
  EDIT = Integrations::PullRequestReviews::EDIT
  REPLY = Integrations::PullRequestReviews::REPLY
  RESOLVE = Integrations::PullRequestReviews::RESOLVE
  CHANGES = Integrations::PullRequestReviews::CHANGES

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400, status: PullRequestReview::STATUS_DONE,
                                        summary_comment_id: "100", review_comment_id: "55", review_posted_at: Time.current)
    @finding = @review.findings.create!(position: 1, fingerprint: "f" * 32, category: PullRequestReview::Finding::CATEGORY_STABILITY,
                                        severity: PullRequestReview::Finding::SEVERITY_MAJOR, effort: PullRequestReview::Finding::EFFORT_QUICK_WIN,
                                        claim: "Queue the retry for its backoff delay", why: "It waits five minutes.", path: "app/jobs/retry_job.rb", line: 12,
                                        host_comment_id: "701")
    @approval = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                          principal_label: "Halon pull request review", action_key: "github.comment_on_pull_request", request_digest: "d", scope: {},
                                          params: {}, required_role: WorkspaceMembership.roles[:admin])
    @review.hold!(@approval, operation: EDIT, given: { reference: "100", body: "Summary" }, purpose: nil)
    @calls = []
    Integrations::PullRequestReviews.stubs(:public?).returns(false)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| (@calls << [ called, given ]) && true }.returns("800")
    PullRequestReviewPosting.any_instance.stubs(:authorizer).returns(->(_tool, _arguments, &run) { run.call })
  end

  test "a reply and its resolve wait behind a held post instead of being lost, and go up in order once it is approved" do
    posting = PullRequestReviewPosting.new(@review.reload)

    assert_nil posting.reply!(@finding, "Fixed in bbbbbbb.", then_resolve: true)
    assert_empty @calls, "nothing is posted while a post waits on its approval"
    assert_equal [ { "kind" => "reply", "finding_id" => @finding.id, "body" => "Fixed in bbbbbbb.", "resolve" => true } ], @review.reload.pending_posts

    approve!

    assert_equal [ EDIT, REPLY, RESOLVE ], @calls.map(&:first).first(3)
    assert_equal "Fixed in bbbbbbb.", @calls.second.last[:body]
    assert_empty @review.reload.pending_posts
    assert_includes @finding.reload.thread_comments, "800"
  end

  test "a thread's answer moves the finding and its reply waits, never raised, so the job's retry has nothing left to lose" do
    FirefightAi::ReviewThread.any_instance.stubs(:answer)
                         .returns(FirefightAi::ReviewThread::Answer.new(answer: "You are right.", withdraw: true, reason: "The job already waits."))
    PullRequestReviewPosting.any_instance.stubs(:file).returns("12 perform_later")
    reply = Integrations::PullRequestReviews::Signal.new(kind: Integrations::PullRequestReviews::COMMENTED, repository: "acme/api", number: 7, reference: "r",
                                                         comment: "88", thread: "701", body: "It waits already", author: "ada")

    assert_nothing_raised { PullRequestReviewThreads.new(@finding).answer!(reply) }

    assert @finding.reload.withdrawn?
    assert_equal [ [ "reply", true ] ], @review.reload.pending_posts.map { |post| post.values_at("kind", "resolve") }
  end

  test "a finding's comments edited while a post is held wait once, and go up as the finding stands then" do
    posting = PullRequestReviewPosting.new(@review.reload)
    @finding.fixed!("b" * 40)

    posting.run!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: @finding)
    posting.run!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: @finding)

    assert_empty @calls
    assert_equal [ { "kind" => "edit", "finding_id" => @finding.id } ], @review.reload.pending_posts

    approve!

    edit = @calls.find { |called, given| called == EDIT && given[:reference] == "701" }
    assert edit, "the line comment's edit went up"
    assert edit.last[:body].start_with?("Fixed in bbbbbbb.")
  end

  test "a declined approval still lets what waited behind it go up" do
    PullRequestReviewPosting.any_instance.stubs(:summary!).returns(nil)
    @review.wait!({ "kind" => "resolve", "finding_id" => @finding.id })
    @approval.update_columns(status: Ability::Approval::STATUS_DENIED)

    perform_enqueued_jobs { PullRequestReviewPosting.decided(@approval, { "review_id" => @review.id }) }

    assert_equal [ RESOLVE ], @calls.map(&:first)
    assert_nil @review.reload.held_approval_id
  end

  test "what waited behind an approval that lapsed goes up with the review's next change" do
    @review.wait!({ "kind" => "resolve", "finding_id" => @finding.id })
    @approval.update_columns(status: Ability::Approval::STATUS_EXPIRED)

    PullRequestReviewPosting.new(@review.reload).run!(PullRequestReview::CHANGE_STARTED)

    assert_equal [ RESOLVE, EDIT ], @calls.map(&:first)
    assert_empty @review.reload.pending_posts
  end

  test "a read is never held" do
    PullRequestReviewPosting.new(@review.reload).changes("a" * 40, "b" * 40)

    assert_equal [ CHANGES ], @calls.map(&:first)
  end

  test "line comments GitHub took but would not read back are matched to their findings later, by the id each carries" do
    @review.release_held!(@approval.id)
    @review.update_columns(review_comment_id: nil, review_posted_at: nil)
    @finding.update_columns(host_comment_id: nil)
    unread = Integrations::PullRequestReviews::Posted.new(reference: "56", comments: [], url: "https://example.com/r56", unread: true)
    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REVIEW }.returns(unread)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == EDIT }.returns("100")

    assert_enqueued_with(job: PullRequestReviewPostJob, args: [ @review.id, nil, PullRequestReviewPosting::ADOPT ]) do
      PullRequestReviewPosting.new(@review.reload).run!(PullRequestReview::CHANGE_FINISHED)
    end
    assert @review.reload.comments_unread?
    assert_nil @finding.reload.host_comment_id

    Integrations::PullRequestReviews.stubs(:posted_comments).returns(nil)
    assert_raises(PullRequestReviewPosting::NotPosted) { PullRequestReviewPosting.new(@review.reload).run!(PullRequestReviewPosting::ADOPT) }

    Integrations::PullRequestReviews.stubs(:posted_comments)
                                    .returns([ Integrations::PullRequestReviews::PostedComment.new(reference: "901", url: "https://example.com/c901",
                                                                                                  body: "Words\n\n#{PullRequestReview::Comments.mark_of(@finding)}") ])
    PullRequestReviewPosting.new(@review.reload).run!(PullRequestReviewPosting::ADOPT)

    assert_equal [ "901", "https://example.com/c901" ], @finding.reload.values_at(:host_comment_id, :host_comment_url)
    assert_not @review.reload.comments_unread?
  end

  test "a push reads back unmatched line comments before it checks each thread's fix" do
    @review.release_held!(@approval.id)
    @review.update_columns(comments_unread: true)
    @finding.update_columns(host_comment_id: nil)
    Integrations::GithubApp.stubs(:bot_login).returns("firefight-app[bot]")
    Integrations::PullRequestReviews.stubs(:posted_comments)
                                    .returns([ Integrations::PullRequestReviews::PostedComment.new(reference: "901", url: nil, body: PullRequestReview::Comments.mark_of(@finding)) ])
    PullRequestReview::Start.stubs(:call).returns(PullRequestReview.new(status: PullRequestReview::STATUS_QUEUED, head_sha: "b" * 40))
    pushed = Integrations::PullRequestReviews::Signal.new(kind: Integrations::PullRequestReviews::PUSHED, repository: "acme/api", number: 7, reference: "p",
                                                          head_sha: "b" * 40)

    assert_enqueued_with(job: PullRequestReviewRecheckJob, args: [ @finding.id, "a" * 40, "b" * 40 ]) do
      PullRequestReviewSignals.new(@row).receive!(pushed)
    end
  end

  private

  def approve!
    @approval.update_columns(status: Ability::Approval::STATUS_APPROVED)
    PullRequestReviewPosting.new(@review.reload).run!(PullRequestReviewPosting::RESUMED, approval_id: @approval.id)
  end
end
