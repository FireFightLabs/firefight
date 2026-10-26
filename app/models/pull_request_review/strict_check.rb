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

  # The findings holding the check failing.
  def holding_findings = findings.holding.preload(lesson: :source).to_a

  # What the check should say now, or nil when no strict lesson was ever involved and no check was set before.
  def commit_status_due
    return COMMIT_STATUS_FAILING if holding_findings.any?
    return COMMIT_STATUS_PASSING if commit_status || findings.joins(:lesson).where(chat_memories: { strict: true }).exists?

    nil
  end

  # The words the code host shows beside the check, short since some hosts cut them.
  def commit_status_words(state)
    return "Every finding from a strict lesson is fixed or overridden." if state == COMMIT_STATUS_PASSING

    held = holding_findings
    labels = held.filter_map(&:lesson_label).uniq.to_sentence
    "#{held.size} #{'finding'.pluralize(held.size)} from a strict lesson #{held.size == 1 ? 'is' : 'are'} open: #{labels}."
  end

  # Claims setting state on sha, once. Guarded, so of two workers deciding the same thing only one calls the host.
  def claim_commit_status!(state, sha)
    moved = self.class.where(id: id).where("commit_status IS DISTINCT FROM :state OR commit_status_sha IS DISTINCT FROM :sha", state: state, sha: sha)
                .update_all(commit_status: state, commit_status_sha: sha, commit_status_error: nil, updated_at: Time.current) > 0
    reload if moved
    moved
  end

  # The host refused, so the next change tries again, and why is kept for whoever looks.
  def commit_status_failed!(error)
    update_columns(commit_status: nil, commit_status_sha: nil, commit_status_error: error.to_s.truncate(250), updated_at: Time.current)
  end
end
