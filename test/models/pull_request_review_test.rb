require "test_helper"

class PullRequestReviewTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a new review is queued and live, and one pull request has one live review at a time" do
    review = create_review

    assert_equal PullRequestReview::STATUS_QUEUED, review.status
    assert review.live?
    assert_raises(ActiveRecord::RecordNotUnique) { create_review }
  end

  test "a rehearsal of the same pull request runs beside a live review" do
    create_review

    assert create_review(rehearsal: true).live?
  end

  test "a worker claims a queued review once, a second worker loses, and the review says it started" do
    review = create_review
    announced = capture_announcements { assert review.claim!(by: "job-1") }

    assert_not PullRequestReview.find(review.id).claim!(by: "job-2")
    assert_equal PullRequestReview::STATUS_RUNNING, review.status
    assert_equal 1, review.attempts
    assert_not_nil review.started_at
    assert_equal [ [ review.id, nil, PullRequestReview::CHANGE_STARTED ] ], announced
  end

  test "a review whose worker stopped renewing its lease is taken over" do
    review = create_review
    review.claim!(by: "job-1")
    review.update_columns(lease_until: 1.minute.ago)

    assert PullRequestReview.find(review.id).claim!(by: "job-2")
    assert_not review.renew_lease!(by: "job-1")
  end

  test "a finished review leaves room for the next one and says how it ended" do
    review = create_review
    review.claim!(by: "job-1")
    announced = capture_announcements { assert review.finish!(status: PullRequestReview::STATUS_DONE) }

    assert_not review.finish!(status: PullRequestReview::STATUS_FAILED)
    assert_equal [ PullRequestReview::CHANGE_FINISHED ], announced.map(&:last)
    assert create_review.live?
  end

  test "a rehearsal is never announced" do
    review = create_review(rehearsal: true)

    assert_empty(capture_announcements { review.claim!(by: "job-1") })
  end

  test "merged is learned once" do
    review = create_review
    at = 2.hours.ago

    assert review.merged!(at)
    assert_not review.merged!(Time.current)
    assert_in_delta at, review.reload.merged_at, 1
  end

  private

  def create_review(rehearsal: false)
    PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "a" * 40, trigger: PullRequestReview::TRIGGER_REQUESTED,
                              max_spend_cents: 400, rehearsal: rehearsal)
  end

  def capture_announcements(&)
    announced = []
    subscriber = ActiveSupport::Notifications.subscribe(PullRequestReview::EVENT) do |event|
      announced << event.payload.values_at(:review_id, :finding_id, :change)
    end
    yield
    announced
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
