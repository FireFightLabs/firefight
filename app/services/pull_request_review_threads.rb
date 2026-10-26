# What Halon says on the threads its review started, after the review posted. A push that touched a finding's file is
# checked against it: the thread is told whether the fix holds, and a fixed one is resolved, its comment edited to say
# which commit fixed it. A person's reply gets an answer, and when they showed the finding wrong Halon says so, withdraws
# it and resolves the thread. The model reads, and every read and post goes through the connection's own tools as Halon's
# review agent (PullRequestReviewPosting).
class PullRequestReviewThreads
  # A reply is answered from the code around the finding at the pull request's newest head.
  def initialize(finding)
    @finding = finding
    @review = finding.review
    @posting = PullRequestReviewPosting.new(@review)
  end

  # base is the head the finding's review read, head the commit the push moved the pull request to.
  def recheck!(base, head)
    return unless @finding.open? && @finding.host_comment_id && @finding.path.present? && @finding.claim_recheck!(head)

    changes = @posting.changes(base, head).to_s
    return unless changes.include?(@finding.path)

    found = FirefightAi::ReviewThread.new(@review.workspace, inferable: @review).recheck(finding: @finding.as_posted, changes: changes,
                                                                                          code: @posting.file(@finding.path, head, @finding.line))
    fixed = (true if found.fixed?) || (false if found.not_fixed?)
    @posting.reply!(@finding, PullRequestReview::Comments.recheck_reply(fixed, found.words, head))
    return unless found.fixed? && @finding.fixed!(head)

    @posting.resolve!(@finding)
  end

  # A person's reply on the finding's thread, as the code host sent it.
  def answer!(signal)
    return unless @finding.claim_answer!(signal.comment)

    head = signal.head_sha.presence || PullRequestReview.latest_of(@review.workspace, @review.repository, @review.number)&.head_sha || @review.head_sha
    code = @finding.path.present? ? @posting.file(@finding.path, head, @finding.line) : nil
    said = FirefightAi::ReviewThread.new(@review.workspace, inferable: @review).answer(finding: @finding.as_posted, thread: nil, reply: signal.body, code: code)
    if said.withdraw? && @finding.withdraw!(said.reason)
      @posting.reply!(@finding, PullRequestReview::Comments.withdrawn_reply(said.answer, said.reason))
      @posting.resolve!(@finding)
    elsif said.answer.present?
      @posting.reply!(@finding, said.answer)
    end
  end
end
