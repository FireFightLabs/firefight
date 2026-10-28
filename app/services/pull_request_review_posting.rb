# Puts Halon's review of a pull request on the pull request, through the code host connection it read through. The
# summary comment goes up as the review starts and is edited as each finding is written. A serious finding gets a comment
# of its own at once, so everyone on the pull request is notified. Once the review is done each finding in the diff goes
# on its line and the rest in the review's body: in one review call on a host that posts it whole, or one line comment at
# a time, each kept as it lands, on a host whose review is several calls. A public repository gets each finding in code
# terms with a link to its evidence in Firefight. Every call is one of the connection's own tools, made as Halon's review
# agent through the gateway, and one an approval rule holds parks the review's posting until it is decided. A reply, a
# thread resolved or a finding's comments edited while a post is held waits with the review and goes up once the
# approval is decided, so what a thread or a push already settled is never lost. A reply the host refuses for good, as on
# a thread whose comment was deleted, goes up as a comment in the pull request's conversation naming its finding, and one
# refused there too is kept on the review's page with why.
class PullRequestReviewPosting
  # Raised so the job tries again later.
  class NotPosted < StandardError; end

  # A call an approval rule holds, or one waiting behind it. The posting picks up once the approval is decided.
  class Held < StandardError; end

  # What a reply kept on the review's page for want of access says after the host's words.
  ACCESS_HINT = "Firefight's access to the code host may need fixing under Integrations.".freeze

  RESUMED = "resumed".freeze
  # What a decided approval queues when it was declined: the posts that waited behind it.
  CAUGHT_UP = "caught_up".freeze
  # Line comments a review posted that the host would not say the ids of, read back later.
  ADOPT = "adopt".freeze
  ADOPT_WAIT = 1.minute

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
      # Only what waited goes up, never the declined call again.
      PullRequestReviewPostJob.perform_later(review.id, nil, CAUGHT_UP) if review.pending_posts.present?
    end
  end

  def initialize(review)
    @review = review
  end

  def run!(change, finding: nil, approval_id: nil)
    return unless postable?

    post_pending! unless [ RESUMED, CAUGHT_UP ].include?(change) || @review.pending_posts.blank? || @review.holding?
    case change
    when RESUMED then resume!(approval_id)
    when CAUGHT_UP then post_pending!
    when ADOPT then adopt!
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
    edit_finding!(finding) if finding && (!finding.open? || finding.lesson_id.present?)
    summary!
  end

  # A finding's line comment and its own comment written as the finding stands now. An edit that waits behind a held
  # post is written as the finding stands once it goes up.
  def edit_finding!(finding)
    publicize!(finding)
    later = { "kind" => PullRequestReview::PENDING_EDIT, "finding_id" => finding.id }
    if finding.host_comment_id
      call!(Integrations::PullRequestReviews::EDIT, reference: finding.host_comment_id, body: writer.finding(finding), line: true, later: later)
    end
    call!(Integrations::PullRequestReviews::EDIT, reference: finding.serious_comment_id, body: writer.serious(finding), later: later) if finding.serious_comment_id
  end

  # Replies on a finding's thread and keeps what was said there. then_resolve resolves the thread once the reply went up,
  # which a held reply carries to its approval.
  # A reply held or waiting behind a held post goes up once the approval is decided, its resolve after it, and answers
  # nil now. recheck marks what a push's check said, of which only the newest waits. The first reply the host refuses for
  # good goes up in the conversation instead (reply_elsewhere!), and its thread is left as it is. The thread is never
  # asked again, and every later reply is kept on the review's page, so a push never adds another comment.
  def reply!(finding, body, then_resolve: false, recheck: false)
    return keep_on_page!(finding, body, "Its thread refused an earlier reply, so this one is kept here. #{finding.thread_refusal}") if finding.thread_refusal.present?

    waiting = { "kind" => PullRequestReview::PENDING_REPLY, "finding_id" => finding.id, "body" => body, "resolve" => then_resolve, "recheck" => recheck }
    posted = call!(Integrations::PullRequestReviews::REPLY, reference: finding.host_comment_id, body: body,
                                                            purpose: { "record" => "reply", "finding_id" => finding.id, "body" => body, "resolve" => then_resolve },
                                                            later: waiting, explained: true, refused: thread_refused(finding, body, recheck))
    return unless posted

    finding.said!(comment: posted, author: SystemAgent::HALON, body: body, halon: true)
    resolve!(finding) if then_resolve
    posted
  end

  # A reply the finding's thread refused for good, posted as a comment in the pull request's conversation that names the
  # finding and links to its comment. Kept as said on the thread without a comment of its own, so a later answer reads it
  # but no reply is matched to it. One refused there too, for any reason, is kept on the review's page with both reasons.
  # One that waits behind a held post goes up once the approval is decided, as a reply does.
  def reply_elsewhere!(finding, body, refused, recheck: false)
    waiting = { "kind" => PullRequestReview::PENDING_REPLY, "finding_id" => finding.id, "body" => body, "resolve" => false, "recheck" => recheck, "refused" => refused }
    posted = call!(Integrations::PullRequestReviews::COMMENT, body: PullRequestReview::Comments.elsewhere_reply(finding, body),
                                                              purpose: { "record" => "reply_elsewhere", "finding_id" => finding.id, "body" => body, "refused" => refused },
                                                              later: waiting, explained: true, refused: conversation_refused(finding, body, refused))
    finding.said!(comment: nil, author: SystemAgent::HALON, body: body, halon: true) if posted
    posted
  end

  def resolve!(finding)
    call!(Integrations::PullRequestReviews::RESOLVE, reference: finding.host_comment_id,
                                                     later: { "kind" => PullRequestReview::PENDING_RESOLVE, "finding_id" => finding.id })
  end

  # Line comments a whole review posted that the host would not say the ids of, matched now to their findings by the id
  # each comment carries, so their threads are followed after a push and their replies answered. The read is one of the
  # connection's tools, made as Halon's review agent through the gateway. A read that fails is tried again by the job, and
  # a review whose connection is gone, or whose host cannot read them back, stops waiting for it.
  def adopt!
    return unless @review.comments_unread?
    return @review.update_columns(comments_unread: false, updated_at: Time.current) unless postable? && Integrations::PullRequestReviews.reads_back?(@review.integration)

    waiting = @review.findings.select { |finding| on_line?(finding) && finding.host_comment_id.blank? }
    comments = call!(Integrations::PullRequestReviews::POSTED_COMMENTS, reference: @review.review_comment_id)
    raise NotPosted, "The line comments of PR ##{@review.number} in #{@review.repository} could not be read back." if comments.nil?

    waiting.each do |finding|
      found = comments.find { |comment| comment.body.to_s.include?(PullRequestReview::Comments.mark_of(finding)) }
      finding.posted_on_line!(found.reference, url: found.url) if found
    end
    @review.update_columns(comments_unread: false, updated_at: Time.current)
  end

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
    if posted.unread && on_lines.any?
      @review.update_columns(comments_unread: true, updated_at: Time.current)
      PullRequestReviewPostJob.set(wait: ADOPT_WAIT).perform_later(@review.id, nil, ADOPT)
    end
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
  # the host turns down never stops the rest. quiet leaves a refusal unlogged for a call that is tried again another way,
  # refused is handed the refusal once it is logged, and explained keeps the host's words for it in the activity log.
  # A call an approval rule holds parks the posting with what to record once it runs, and nothing is posted while it waits,
  # so one review never holds two approvals. A post given later waits with the review then, and answers nil, where any
  # other raises Held to stop what it was part of. A read is never held.
  def call!(operation, quiet: false, purpose: nil, approval_id: nil, later: nil, explained: false, refused: nil, **given)
    if approval_id.nil? && !Integrations::PullRequestReviews::READS.include?(operation) && @review.holding?
      raise Held unless later
      return if @review.wait!(later)
    end

    Integrations::PullRequestReviews.call!(@review.integration_environment, operation, authorize: authorizer(approval_id, explained: explained),
                                                                                         repository: @review.repository, number: @review.number, **given)
  rescue AbilityGateway::PendingApproval => pending
    @review.hold!(pending.approval, operation: operation, given: given, purpose: purpose)
    raise Held unless later
  rescue Integrations::Error, AbilityGateway::Denied => error
    unless quiet
      Rails.logger.warn({ event: "pull_request_review.post_failed", pull_request_review_id: @review.id, operation: operation,
                          error: error.class.name, message: error.message.truncate(300) }.to_json)
    end
    refused&.call(error)
    nil
  end

  # What follows a refused reply on a finding's thread. One refused for Firefight's own access to the code host, its
  # credential, a permission or the repository, says nothing about the thread, so it is kept on the review's page with a
  # hint and the thread is asked again next time. Only when the host refused it for good, the thread's refusal is kept on
  # the finding and the same words go in the conversation, once. A reply another worker already found refused
  # meanwhile is kept on the review's page. A rate limit or a slow host, a tool switched off or a call the gateway denied
  # leaves it as it was.
  def thread_refused(finding, body, recheck)
    lambda do |error|
      next keep_on_page!(finding, body, "#{refusal_words(error)} #{ACCESS_HINT}") if Integrations::PullRequestReviews.not_authorized?(error)
      next unless Integrations::PullRequestReviews.refused_for_good?(error)
      next keep_on_page!(finding, body, "#{refusal_words(error)} #{ACCESS_HINT}") if Integrations::PullRequestReviews.not_found?(error) && !pull_request_readable?

      words = refusal_words(error)
      if finding.thread_refused!(words)
        reply_elsewhere!(finding, body, words, recheck: recheck)
      else
        keep_on_page!(finding, body, "Its thread refused an earlier reply, so this one is kept here. #{words}")
      end
    end
  end

  # A comment the host says is not there may be the connection's access to the repository lost rather than the comment
  # gone, so the pull request's conversation is read through the same connection to tell them apart.
  def pull_request_readable?
    !call!(Integrations::PullRequestReviews::CONVERSATION, since: Time.current).nil?
  rescue Held
    false
  end

  def keep_on_page!(finding, body, reason)
    finding.unposted_reply!(body: body, reason: reason)
    Rails.logger.warn({ event: "pull_request_review.reply_unposted", pull_request_review_finding_id: finding.id }.to_json)
    nil
  end

  # A reply the conversation refused too, whatever the reason, kept on the review's page with both reasons.
  def conversation_refused(finding, body, thread_words)
    lambda do |error|
      keep_on_page!(finding, body, "It could not go on the finding's thread. #{thread_words} It could not go in the pull request's conversation either. #{refusal_words(error)}")
    end
  end

  # A refusal in words a workspace member reads, the host's own or what the gateway refused.
  def refusal_words(error)
    return "Halon's pull request review is not allowed to post there." if error.is_a?(AbilityGateway::Denied)

    Integrations::Sentence.of(error.message) || "The code host refused it."
  end

  # The held call made once its approval was given, with exactly what was held, recorded as it would have been, then
  # everything since caught up.
  def resume!(approval_id)
    held = @review.held_post(approval_id)
    return unless held

    given = held.given
    given = given.merge(comments: given[:comments].map { |comment| Integrations::PullRequestReviews::LineComment.new(**comment.symbolize_keys) }) if given[:comments]
    result = call!(held.operation, approval_id: approval_id, **held_refusal(held.purpose), **given)
    if result
      record!(held.purpose, result)
    elsif held.purpose["record"] == "whole"
      # The whole review the host refused once approved goes again the usual way, its fallback and retry included.
      @review.release_review_post!
    end
    post_pending!(@review.release_with_pending!(approval_id))
    @review.done? ? finished! : summary!
  end

  # What waited behind a held post, oldest first: after its approval is decided, or with the review's next change once
  # an approval lapsed. Each is taken off the queue once sent. One held again is replayed by its own approval, and every
  # post after it waits on.
  def post_pending!(posts = @review.release_with_pending!)
    posts.each do |post|
      break if @review.holding?

      post_waiting!(post)
      @review.sent_pending!(post)
    end
  end

  # A held reply or its comment in the conversation, refused once approved, goes the same way it would have unheld.
  def held_refusal(purpose)
    finding = (finding_of(purpose) if %w[reply reply_elsewhere].include?(purpose["record"]))
    return {} unless finding

    refused = purpose["record"] == "reply" ? thread_refused(finding, purpose["body"], false) : conversation_refused(finding, purpose["body"], purpose["refused"])
    { explained: true, refused: refused }
  end

  def post_waiting!(post)
    finding = PullRequestReview::Finding.find_by(id: post["finding_id"])
    return unless finding

    case post["kind"]
    when PullRequestReview::PENDING_REPLY
      if post["refused"].present?
        reply_elsewhere!(finding, post["body"], post["refused"], recheck: post["recheck"] == true)
      else
        reply!(finding, post["body"], then_resolve: post["resolve"] == true, recheck: post["recheck"] == true)
      end
    when PullRequestReview::PENDING_RESOLVE then resolve!(finding)
    when PullRequestReview::PENDING_EDIT then edit_finding!(finding)
    end
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
    when "reply_elsewhere" then finding_of(purpose)&.said!(comment: nil, author: SystemAgent::HALON, body: purpose["body"], halon: true)
    end
  end

  def finding_of(purpose) = PullRequestReview::Finding.find_by(id: purpose["finding_id"])

  def findings_of(ids) = PullRequestReview::Finding.where(id: Array(ids)).index_by(&:id).values_at(*Array(ids)).compact

  def authorizer(approval_id, explained: false)
    review = @review
    ->(tool, arguments, &run) { review.authorize_post!(tool, arguments, approval_id: approval_id, explained: explained, &run) }
  end
end
