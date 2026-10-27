# The check a review sets on its pull request's head commit once a strict lesson is involved. It fails while a finding
# from a strict lesson is open and nobody overrode it, and passes once each is fixed, withdrawn or overridden. A review
# no strict lesson ever touched sets no check at all, so a pull request is not given one it never needed.
module PullRequestReview::StrictCheck
  extend ActiveSupport::Concern

  COMMIT_STATUS_PASSING = "passing".freeze
  COMMIT_STATUS_FAILING = "failing".freeze
  COMMIT_STATUSES = [ COMMIT_STATUS_PASSING, COMMIT_STATUS_FAILING ].freeze

  included do
    validates :commit_status, inclusion: { in: COMMIT_STATUSES }, allow_nil: true
  end

  # Every review of the same pull request people see, each head's, since a finding on an earlier head holds until it is
  # fixed whichever review found it.
  def reviews_of_pull_request
    PullRequestReview.seen.where(workspace_id: workspace_id, number: number).where("lower(repository) = ?", repository.downcase)
  end

  # The findings holding the check failing, the same problem found again on a later head counted once.
  def holding_findings
    PullRequestReview::Finding.once_per_problem(
      PullRequestReview::Finding.holding.where(pull_request_review_id: reviews_of_pull_request.select(:id)).preload(:review, lesson: :source).order(:created_at).to_a
    )
  end

  # What the check should say now, or nil when no strict lesson was ever involved and no check was set before.
  def commit_status_due
    return COMMIT_STATUS_FAILING if holding_findings.any?

    reviews = reviews_of_pull_request
    strict_before = PullRequestReview::Finding.where(pull_request_review_id: reviews.select(:id)).joins(:lesson).where(chat_memories: { strict: true }).exists?
    return COMMIT_STATUS_PASSING if strict_before || reviews.where.not(commit_status: nil).exists?

    nil
  end

  # The words the code host shows beside the check, short since some hosts cut them.
  # A public repository is never told which incident or pull request a lesson came from.
  def commit_status_words(state, public: false)
    return "Every finding from a strict lesson is fixed or overridden." if state == COMMIT_STATUS_PASSING

    held = holding_findings
    open = "#{held.size} #{'finding'.pluralize(held.size)} from a strict lesson #{held.size == 1 ? 'is' : 'are'} open"
    return "#{open}." if public

    "#{open}: #{held.filter_map(&:lesson_label).uniq.to_sentence}."
  end

  # Claims setting state on sha, once. Guarded, so of two workers deciding the same thing only one calls the host.
  def claim_commit_status!(state, sha)
    moved = self.class.where(id: id).where("commit_status IS DISTINCT FROM :state OR commit_status_sha IS DISTINCT FROM :sha", state: state, sha: sha)
                .update_all(commit_status: state, commit_status_sha: sha, commit_status_error: nil, updated_at: Time.current) > 0
    reload if moved
    moved
  end

  # Why the check could not be set, in words for the Lessons tab, or nil while it was set.
  def commit_status_problem
    return nil if commit_status_error.blank?

    host = integration&.name.presence || "the code host"
    error = commit_status_error.strip
    "Couldn't set the check on #{host}: #{error.match?(/[.!?]\z/) ? error : "#{error}."}"
  end

  # The host refused, so the next change tries again, and why is kept for whoever looks.
  def commit_status_failed!(error)
    update_columns(commit_status: nil, commit_status_sha: nil, commit_status_error: error.to_s.truncate(250), updated_at: Time.current)
  end
end
