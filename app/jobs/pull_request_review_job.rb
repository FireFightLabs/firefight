# Runs one pull request review (PullRequestReview::Runner). The review is a loop of model calls and tools for minutes,
# so it runs on the investigations worker. A worker that dies hands the review to the retry, which carries on from the
# parts already reviewed and the findings already written.
class PullRequestReviewJob < ApplicationJob
  queue_as :investigations

  # Marked failed only once the retries are gone, so a deadlock or a killed worker resumes rather than burning the review.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.mark_failed(error)
  end

  # Retrying gives the same answer, so the review ends now rather than three attempts later.
  discard_on FirefightAi::TerminalError do |job, error|
    job.mark_failed(error)
  end
  # The review itself is gone, or something it read is. Either way it ends, so its pull request can be reviewed again.
  discard_on ActiveRecord::RecordNotFound do |job, error|
    job.mark_failed(error)
  end
  # The worker that holds the lease is already doing this work.
  discard_on PullRequestReview::Runner::LeaseLost

  def perform(review_id)
    review = PullRequestReview.find(review_id)
    return unless review.claim!(by: job_id)
    return give_up(review, PullRequestReview::TOO_MANY_ATTEMPTS, cause: "too many attempts") if review.worn_out?

    work(review)
  end

  # Only the plain sentence is kept on the review, and the cause is logged for whoever debugs it.
  def mark_failed(error)
    review_id, = arguments
    review = PullRequestReview.find_by(id: review_id)
    give_up(review, self.class.stopped_because(error), cause: error.try(:reason) || "#{error.class.name}: #{error.message}") if review
  end

  def self.stopped_because(error)
    case error
    when FirefightAi::OutOfCredit then PullRequestReview::OUT_OF_CREDIT
    when Integrations::Error then PullRequestReview::COULD_NOT_READ
    else PullRequestReview::GAVE_UP
    end
  end

  private

  def work(review)
    result = PullRequestReview::Runner.new(review, by: job_id).run
    review.finish!(status: result.status, error_summary: result.error_summary)
    # Nothing reads code once the review is over, and a box costs while it runs. A retry keeps it, since it reads there again.
    Integrations::CodeReading.close(review.code_box_key)
  rescue StandardError
    review.release!(by: job_id)
    raise
  end

  def give_up(review, reason, cause:)
    Rails.logger.warn({ event: "pull_request_review.failed", pull_request_review_id: review.id, cause: cause }.to_json)
    review.finish!(status: PullRequestReview::STATUS_FAILED, error_summary: reason)
    Integrations::CodeReading.close(review.code_box_key)
  end
end
