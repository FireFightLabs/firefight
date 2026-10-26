# Puts Halon's review of a pull request on the pull request, through the code host connection it read through. The
# summary comment goes up as the review starts and is edited as each finding is written. A serious finding gets a comment
# of its own at once, so everyone on the pull request is notified. Once the review is done it posts as one review: a
# comment on the line of each finding in the diff, and the rest in its body. Every call is one of the connection's own
# tools, made as Halon's review agent through the gateway, so it is in the activity log like any other.
class PullRequestReviewPosting
  def self.changed!(review_id:, finding_id:, change:)
    PullRequestReviewPostJob.perform_later(review_id, finding_id, change)
  end

  def initialize(review)
    @review = review
  end

  def run!(change, finding: nil)
    return unless postable?

    case change
    when PullRequestReview::CHANGE_STARTED, PullRequestReview::CHANGE_FAILED then summary!
    when PullRequestReview::CHANGE_FINDING_ADDED then finding_added!(finding)
    when PullRequestReview::CHANGE_FINDING_CHANGED, PullRequestReview::CHANGE_FINDING_WITHDRAWN then finding_changed!(finding)
    when PullRequestReview::CHANGE_FINISHED then finished!
    end
  end

  # The summary comment as the pull request's newest review stands, posted the first time and edited after. A finding
  # of an earlier review that a push fixed edits the same comment.
  def summary!
    current = PullRequestReview.latest_of(@review.workspace, @review.repository, @review.number) || @review
    body = PullRequestReview::Comments.summary(current, current.pull_request_findings)
    reference = current.summary_reference
    if reference
      current.summary_posted!(reference) if current.summary_comment_id.blank?
      return call!(Integrations::PullRequestReviews::EDIT, reference: reference, body: body)
    end

    posted = call!(Integrations::PullRequestReviews::COMMENT, body: body)
    current.summary_posted!(posted) if posted
  end

  # A finding a later push fixed or a person showed was wrong: its line comment and its own comment say so, and the
  # summary is edited.
  def finding_changed!(finding)
    summary!
    return unless finding && !finding.open?

    call!(Integrations::PullRequestReviews::EDIT, reference: finding.host_comment_id, body: PullRequestReview::Comments.finding(finding), line: true) if finding.host_comment_id
    call!(Integrations::PullRequestReviews::EDIT, reference: finding.serious_comment_id, body: PullRequestReview::Comments.serious(finding)) if finding.serious_comment_id
  end

  # Replies on a finding's thread.
  def reply!(finding, body) = call!(Integrations::PullRequestReviews::REPLY, reference: finding.host_comment_id, body: body)

  def resolve!(finding) = call!(Integrations::PullRequestReviews::RESOLVE, reference: finding.host_comment_id)

  # What a push changed, from one commit to another, and a file at a commit, read as Halon's review agent.
  def changes(base, head) = call!(Integrations::PullRequestReviews::CHANGES, base: base, commit: head)

  def file(path, commit, line) = call!(Integrations::PullRequestReviews::FILE, path: path, commit: commit, start: line)

  private

  # Only a review people see, through a connection still there, that can post a review.
  def postable?
    !@review.rehearsal? && @review.integration_environment.present? && Integrations::PullRequestReviews.hosts?(@review.integration)
  end

  def finding_added!(finding)
    summary!
    return unless finding&.serious? && finding.open? && finding.serious_comment_id.blank? && !@review.posted_before?(finding)

    posted = call!(Integrations::PullRequestReviews::COMMENT, body: PullRequestReview::Comments.serious(finding))
    finding.serious_posted!(posted) if posted
  end

  # The review itself, once, then the summary as it ends. A review the host took none of is handed back, so the job's
  # retry posts it.
  def finished!
    if @review.claim_review_post!
      unless post_review!
        @review.release_review_post!
        raise NotPosted, "The code host took nothing of the review of PR ##{@review.number} in #{@review.repository}."
      end
    end
    summary!
  end

  # Raised so the job tries again later.
  class NotPosted < StandardError; end

  # True once the review is on the pull request, or when it found nothing to post.
  def post_review!
    fresh = @review.findings.still_open.reject { |finding| @review.posted_before?(finding) }
    return true if fresh.empty?

    on_lines, outside = fresh.partition { |finding| finding.path.present? && finding.line.present? && !finding.outside_diff? }
    posted = review!(on_lines, outside) || review!([], on_lines + outside)
    return false unless posted

    @review.review_posted!(posted.reference)
    placed = on_lines.zip(posted.comments).map { |finding, reference| reference.present? && finding.posted_on_line!(reference) && finding }
    unplaced = on_lines - placed.compact_blank
    call!(Integrations::PullRequestReviews::COMMENT, body: PullRequestReview::Comments.unplaced(unplaced)) if posted.comments.any? && unplaced.any?
    true
  end

  # One review with its line comments, or nil when the host refused it.
  def review!(on_lines, outside)
    comments = on_lines.map do |finding|
      Integrations::PullRequestReviews::LineComment.new(path: finding.path, line: finding.line, body: PullRequestReview::Comments.finding(finding))
    end
    call!(Integrations::PullRequestReviews::REVIEW, commit: @review.head_sha, comments: comments,
                                                     body: PullRequestReview::Comments.review_body(@review, on_lines, outside), quiet: on_lines.any?)
  end

  # One call through the connection's tool, as Halon's review agent. A refusal is logged and answers nil, so one comment
  # the host turns down never stops the rest. quiet leaves a refusal unlogged for a call that is tried again another way.
  def call!(operation, quiet: false, **given)
    Integrations::PullRequestReviews.call!(@review.integration_environment, operation, authorize: authorizer, repository: @review.repository,
                                                                                         number: @review.number, **given)
  rescue Integrations::Error, AbilityGateway::Denied, AbilityGateway::PendingApproval => error
    unless quiet
      Rails.logger.warn({ event: "pull_request_review.post_failed", pull_request_review_id: @review.id, operation: operation,
                          error: error.class.name, message: error.message.truncate(300) }.to_json)
    end
    nil
  end

  def authorizer
    review = @review
    ->(tool, arguments, &run) { review.authorize_post!(tool, arguments, &run) }
  end
end
