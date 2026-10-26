# Sets a review's check on its pull request's head commit through the code host that holds it, once a strict lesson is
# involved: failing while a finding from one is open and nobody overrode it, passing once none is. The same state on
# the same commit is set once, and a host that refuses is tried again at the next change, with why kept on the review.
class PullRequestReviewCheckService
  def initialize(review)
    @review = review
  end

  # Returns the state set, or nil when nothing was due or the host could not take it.
  def update!
    return nil if @review.rehearsal?

    state = @review.check_due
    row = @review.integration_environment
    return nil unless state && row && Integrations::ReviewChecks.sets?(row.integration)
    return nil unless @review.claim_check!(state, @review.head_sha)

    check = Integrations::ReviewChecks::Check.new(state: state, description: @review.check_words(state), url: link)
    Integrations::ReviewChecks.set!(row, repository: @review.repository, sha: @review.head_sha, check: check)
    state
  rescue Integrations::Error => error
    @review.check_failed!(error.message)
    Rails.logger.info({ event: "pull_request_review.check_not_set", review_id: @review.id, error: error.class.name }.to_json)
    nil
  end

  private

  # The Lessons tab with this review's findings marked, where a person can override one.
  def link
    options = AppUrl.options
    options && Rails.application.routes.url_helpers.memory_url(**options, MemoryController::TAB_QUERY => MemoryController::TAB_LESSONS,
                                                                           MemoryController::REVIEW_QUERY => @review.id)
  end
end
