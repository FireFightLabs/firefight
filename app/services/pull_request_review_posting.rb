# Puts Halon's review of a pull request on the pull request, through the code host connection it read through. The
# summary comment goes up as the review starts and is edited as each finding is written. A serious finding gets a comment
# of its own at once, so everyone on the pull request is notified. Once the review is done each finding in the diff goes
# on its line and the rest in the review's body: in one review call on a host that posts it whole, or one line comment at
# a time, each kept as it lands, on a host whose review is several calls. A public repository gets each finding in code
# terms with a link to its evidence in Firefight. Every call is one of the connection's own tools, made as Halon's review
# agent through the gateway, and one an approval rule holds parks the review's posting until it is decided.
class PullRequestReviewPosting
  # Raised so the job tries again later.
  class NotPosted < StandardError; end

  # A call an approval rule holds, or one waiting behind it. The posting picks up once the approval is decided.
  class Held < StandardError; end

  RESUMED = "resumed".freeze

  def self.changed!(review_id:, finding_id:, change:)
    PullRequestReviewPostJob.perform_later(review_id, finding_id, change)
  end

  # An approval for a held post was decided. Approved, the job makes that call and catches up. Declined, the posting
  # stops holding and waits for the review's next change.
  def self.decided(approval, payload)
    review = PullRequestReview.find_by(id: payload["review_id"])
    return unless review

    if approval.approved?
      PullRequestReviewPostJob.perform_later(review.id, nil, RESUMED, approval.id)
    else
      review.release_held!(approval.id)
      Rails.logger.info({ event: "pull_request_review.post_declined", pull_request_review_id: review.id, approval_id: approval.id }.to_json)
    end
  end

  def initialize(review)
    @review = review
  end

  def run!(change, finding: nil, approval_id: nil)
    return unless postable?

    case change
    when RESUMED then resume!(approval_id)
    when PullRequestReview::CHANGE_STARTED, PullRequestReview::CHANGE_FAILED then summary!
    when PullRequestReview::CHANGE_FINDING_ADDED then finding_added!(finding)
    when PullRequestReview::CHANGE_FINDING_CHANGED, PullRequestReview::CHANGE_FINDING_WITHDRAWN then finding_changed!(finding)
    when PullRequestReview::CHANGE_FINISHED then finished!
    end
  rescue Held
    nil
  end

  # The summary comment as the pull request's newest review stands, posted the first time and edited after. A finding
  # of an earlier review that a push fixed edits the same comment.
  def summary!
    current = PullRequestReview.latest_of(@review.workspace, @review.repository, @review.number) || @review
    body = writer.summary(current, current.pull_request_findings)
    reference = current.summary_reference
    if reference
      current.summary_posted!(reference) if current.summary_comment_id.blank?
      return call!(Integrations::PullRequestReviews::EDIT, reference: reference, body: body)
    end

    posted = call!(Integrations::PullRequestReviews::COMMENT, body: body, purpose: { "record" => "summary", "review_id" => current.id })
    current.summary_posted!(posted) if posted
  end

  # A finding a later push fixed or a person showed was wrong: its line comment and its own comment say so, and the
  # summary is edited. A finding from a lesson is edited while open too, since its comment says whether it holds the
  # check, which an override or a change to the lesson moves.
  def finding_changed!(finding)
    summary!
    return unless finding && (!finding.open? || finding.lesson_id.present?)

    publicize!(finding)
    call!(Integrations::PullRequestReviews::EDIT, reference: finding.host_comment_id, body: writer.finding(finding), line: true) if finding.host_comment_id
    call!(Integrations::PullRequestReviews::EDIT, reference: finding.serious_comment_id, body: writer.serious(finding)) if finding.serious_comment_id
  end

  # Replies on a finding's thread and keeps what was said there. then_resolve resolves the thread once the reply went up,
  # which a held reply carries to its approval.
  def reply!(finding, body, then_resolve: false)
    posted = call!(Integrations::PullRequestReviews::REPLY, reference: finding.host_comment_id, body: body,
                                                            purpose: { "record" => "reply", "finding_id" => finding.id, "body" => body, "resolve" => then_resolve })
    return unless posted

    finding.said!(comment: posted, author: SystemAgent::HALON, body: body, halon: true)
    resolve!(finding) if then_resolve
    posted
  end

  def resolve!(finding) = call!(Integrations::PullRequestReviews::RESOLVE, reference: finding.host_comment_id)

  # What a push changed, from one commit to another, and a file at a commit, read as Halon's review agent.
  def changes(base, head) = call!(Integrations::PullRequestReviews::CHANGES, base: base, commit: head)

  def file(path, commit, line) = call!(Integrations::PullRequestReviews::FILE, path: path, commit: commit, start: line)

  # Whether anyone can read the repository, so what Halon writes there stays in code terms.
  def public?
    @public = Integrations::PullRequestReviews.public?(@review.integration_environment, @review.repository) if @public.nil?
    @public
  end

  private

  # Only a review people see, through a connection still there, that can post a review.
  def postable?
    !@review.rehearsal? && @review.integration_environment.present? && Integrations::PullRequestReviews.hosts?(@review.integration)
  end

  def writer
    @writer ||= PullRequestReview::Comments.new(**Integrations::PullRequestReviews.markup(@review.integration).symbolize_keys,
                                                evidence_page: (evidence_page if public?))
  end

  def evidence_page = AppUrl.absolute(Rails.application.routes.url_helpers.halon_pull_request_review_path(@review))

  # A finding posted on a public repository has its why and failure chain in code terms, written once. When that cannot
  # be written, the finding goes up with its claim, its fix and the link to its evidence only.
  def publicize!(finding)
    return unless public? && finding.public_why.blank?

    rewritten = FirefightAi::PublicFinding.new(@review.workspace, inferable: @review).rewrite(claim: finding.claim, why: finding.why, failure_chain: finding.failure_chain)
    finding.publicized!(why: rewritten.why, failure_chain: rewritten.failure_chain)
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "pull_request_review.public_rewrite_failed", pull_request_review_finding_id: finding.id, error: error.class.name }.to_json)
  end

  def finding_added!(finding)
    summary!
    return unless finding&.serious? && finding.open? && finding.serious_comment_id.blank? && !@review.posted_before?(finding)

    publicize!(finding)
    posted = call!(Integrations::PullRequestReviews::COMMENT, body: writer.serious(finding), purpose: { "record" => "serious", "finding_id" => finding.id })
    finding.serious_posted!(posted) if posted
  end

  # The review itself, then the summary as it ends.
  def finished!
    fresh = @review.findings.still_open.reject { |finding| @review.posted_before?(finding) }
    fresh.each { |finding| publicize!(finding) }
    Integrations::PullRequestReviews.atomic?(@review.integration) ? post_whole!(fresh) : post_by_line!(fresh)
    summary!
  end

  def on_line?(finding) = finding.path.present? && finding.line.present? && !finding.outside_diff?

  # A host that posts a review whole: one call, once. Only a review the host refused whole is posted again with every
  # finding in its body, and one it took none of is handed back for the job's retry.
  def post_whole!(fresh)
    return if fresh.empty? || !@review.claim_review_post!

    on_lines, elsewhere = fresh.partition { |finding| on_line?(finding) }
    posted = review!(on_lines, elsewhere, quiet: on_lines.any?) || (review!([], on_lines + elsewhere) if on_lines.any?)
    unless posted
      @review.release_review_post!
      raise NotPosted, "The code host took nothing of the review of PR ##{@review.number} in #{@review.repository}."
    end
    whole_posted!(posted, on_lines, elsewhere)
  end

  # Each line comment kept with its page. One the host would not say the id of opens at the review.
  def whole_posted!(posted, on_lines, elsewhere)
    @review.review_posted!(posted.reference)
    placed = posted.comments.empty? || posted.unread ? [] : on_lines
    placed.each_with_index do |finding, index|
      reference = posted.comments[index]
      reference.present? ? finding.posted_on_line!(reference, url: posted.urls[index]) : finding.posted_at!(posted.url)
    end
    (on_lines - placed + elsewhere).each { |finding| finding.posted_at!(posted.url) }
  end

  # A host whose review is several calls: each line comment on its own, kept as it lands, so a retry posts only what has
  # not gone up, then the review's body with every finding no line took. A failure stops it for the job's retry.
  def post_by_line!(fresh)
    return if fresh.empty? || @review.review_comment_id.present?

    on_lines, elsewhere = fresh.partition { |finding| on_line?(finding) }
    unplaced = on_lines.reject { |finding| finding.host_comment_id.present? || post_line!(finding) }
    body_posted!(on_lines - unplaced, elsewhere + unplaced)
  end

  # True once the finding's line comment went up, false when the host would not place it on its line.
  def post_line!(finding)
    comment = Integrations::PullRequestReviews::LineComment.new(path: finding.path, line: finding.line, body: writer.finding(finding))
    posted = call!(Integrations::PullRequestReviews::REVIEW, commit: @review.head_sha, comments: [ comment ], body: nil,
                                                             purpose: { "record" => "line", "finding_id" => finding.id })
    raise NotPosted, "A line comment on PR ##{@review.number} in #{@review.repository} did not go up." unless posted

    reference = posted.comments.first
    finding.posted_on_line!(reference, url: posted.urls.first) if reference.present?
    reference.present?
  end

  def body_posted!(placed, elsewhere)
    posted, url = call!(Integrations::PullRequestReviews::COMMENT, body: writer.review_body(@review, placed, elsewhere), with_link: true,
                                                                   purpose: { "record" => "body", "finding_ids" => elsewhere.map(&:id) })
    raise NotPosted, "The review of PR ##{@review.number} in #{@review.repository} did not go up." unless posted

    @review.review_posted!(posted)
    elsewhere.each { |finding| finding.posted_at!(url) }
  end

  # One review with its line comments, or nil when the host refused it.
  def review!(on_lines, elsewhere, quiet: false)
    comments = on_lines.map { |finding| Integrations::PullRequestReviews::LineComment.new(path: finding.path, line: finding.line, body: writer.finding(finding)) }
    call!(Integrations::PullRequestReviews::REVIEW, commit: @review.head_sha, comments: comments, body: writer.review_body(@review, on_lines, elsewhere),
                                                     quiet: quiet, purpose: { "record" => "whole", "on_lines" => on_lines.map(&:id), "elsewhere" => elsewhere.map(&:id) })
  end

  # One call through the connection's tool, as Halon's review agent. A refusal is logged and answers nil, so one comment
  # the host turns down never stops the rest. quiet leaves a refusal unlogged for a call that is tried again another way.
  # A call an approval rule holds parks the posting with what to record once it runs, and nothing is sent while it waits,
  # so one review never holds two approvals.
  def call!(operation, quiet: false, purpose: nil, approval_id: nil, **given)
    raise Held if approval_id.nil? && @review.holding?

    Integrations::PullRequestReviews.call!(@review.integration_environment, operation, authorize: authorizer(approval_id), repository: @review.repository,
                                                                                         number: @review.number, **given)
  rescue AbilityGateway::PendingApproval => pending
    @review.hold!(pending.approval, operation: operation, given: given, purpose: purpose)
    raise Held
  rescue Integrations::Error, AbilityGateway::Denied => error
    unless quiet
      Rails.logger.warn({ event: "pull_request_review.post_failed", pull_request_review_id: @review.id, operation: operation,
                          error: error.class.name, message: error.message.truncate(300) }.to_json)
    end
    nil
  end

  # The held call made once its approval was given, with exactly what was held, recorded as it would have been, then
  # everything since caught up.
  def resume!(approval_id)
    held = @review.held_post(approval_id)
    return unless held

    given = held.given
    given = given.merge(comments: given[:comments].map { |comment| Integrations::PullRequestReviews::LineComment.new(**comment.symbolize_keys) }) if given[:comments]
    result = call!(held.operation, approval_id: approval_id, **given)
    @review.release_held!(approval_id)
    if result
      record!(held.purpose, result)
    elsif held.purpose["record"] == "whole"
      # The whole review the host refused once approved goes again the usual way, its fallback and retry included.
      @review.release_review_post!
    end
    @review.done? ? finished! : summary!
  end

  def record!(purpose, result)
    case purpose.to_h["record"]
    when "summary" then PullRequestReview.find_by(id: purpose["review_id"])&.summary_posted!(result)
    when "serious" then finding_of(purpose)&.serious_posted!(result)
    when "line" then (reference = result.comments.first).present? && finding_of(purpose)&.posted_on_line!(reference, url: result.urls.first)
    when "whole" then whole_posted!(result, findings_of(purpose["on_lines"]), findings_of(purpose["elsewhere"]))
    when "body"
      reference, url = result
      @review.review_posted!(reference)
      findings_of(purpose["finding_ids"]).each { |finding| finding.posted_at!(url) }
    when "reply"
      finding = finding_of(purpose)
      finding&.said!(comment: result, author: SystemAgent::HALON, body: purpose["body"], halon: true)
      resolve!(finding) if finding && purpose["resolve"]
    end
  end

  def finding_of(purpose) = PullRequestReview::Finding.find_by(id: purpose["finding_id"])

  def findings_of(ids) = PullRequestReview::Finding.where(id: Array(ids)).index_by(&:id).values_at(*Array(ids)).compact

  def authorizer(approval_id)
    review = @review
    ->(tool, arguments, &run) { review.authorize_post!(tool, arguments, approval_id: approval_id, &run) }
  end
end
