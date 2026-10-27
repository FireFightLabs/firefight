# What Halon says on the threads its review started, after the review posted. A push that touched a finding's file is
# checked against it: the thread is told whether the fix holds, and a fixed one is resolved, its comment edited to say
# which commit fixed it. A person's reply gets an answer read with the thread so far, and when they showed the finding
# wrong Halon says so, withdraws it and resolves the thread. On a public repository it says so in terms of the code. The
# model reads, and every read and post goes through the connection's own tools as Halon's review agent
# (PullRequestReviewPosting).
class PullRequestReviewThreads
  # Raised so the job tries again later, once the claim is handed back.
  class Unread < StandardError; end

  def initialize(finding)
    @finding = finding
    @review = finding.review
    @posting = PullRequestReviewPosting.new(@review)
  end

  # base is the head the finding's review read, head the commit the push moved the pull request to.
  def recheck!(base, head)
    return unless @finding.open? && @finding.host_comment_id && @finding.path.present? && @finding.claim_recheck!(head)

    begin
      changes = @posting.changes(base, head)
      raise Unread, "What the push changed could not be read." if changes.blank?
      return unless changes.include?(@finding.path)

      found = thread_model.recheck(finding: @finding.as_posted, changes: changes, code: file!(head))
    rescue StandardError
      @finding.release_recheck!(head)
      raise
    end
    fixed = (true if found.fixed?) || (false if found.not_fixed?)
    resolving = found.fixed? && @finding.fixed!(head)
    @posting.reply!(@finding, PullRequestReview::Comments.recheck_reply(fixed, found.words, head), then_resolve: resolving, recheck: true)
  end

  # A person's reply on the finding's thread, as the code host sent it.
  def answer!(signal)
    return unless @finding.claim_answer!(signal.comment)

    begin
      head = signal.head_sha.presence || PullRequestReview.latest_of(@review.workspace, @review.repository, @review.number)&.head_sha || @review.head_sha
      code = @finding.path.present? ? file!(head) : nil
      said = thread_model.answer(finding: @finding.as_posted, thread: @finding.thread_so_far, reply: signal.body, code: code)
    rescue StandardError
      @finding.release_answer!(signal.comment)
      raise
    end
    @finding.said!(comment: signal.comment, author: signal.author, body: signal.body)
    if said.withdraw? && @finding.withdraw!(said.reason)
      @posting.reply!(@finding, PullRequestReview::Comments.withdrawn_reply(said.answer, said.reason), then_resolve: true)
    elsif said.answer.present?
      @posting.reply!(@finding, said.answer)
    end
  end

  private

  def thread_model = FirefightAi::ReviewThread.new(@review.workspace, inferable: @review, public: @posting.public?)

  # The finding's file at head. A file that could not be read is never judged as missing code.
  def file!(head)
    @posting.file(@finding.path, head, @finding.line).presence || raise(Unread, "The finding's file could not be read.")
  end
end
