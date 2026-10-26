# What a code host said about a pull request, acted on for Halon's review of it. Someone adding Firefight as a reviewer or
# asking in a comment starts a review. A pull request that opens is reviewed when the workspace reviews every pull
# request when it opens there. A push to one Halon reviewed is reviewed again, and each open thread's fix is checked. A
# reply from a person on one of Halon's threads gets an answer, and a merge is recorded. A pull request Halon opened that
# merged or closed is read for a lesson. Nothing here names a host.
class PullRequestReviewSignals
  # A push that arrives while the review of an earlier one is still running is tried again this often, until it ends.
  RETRY_WAIT = 2.minutes
  RETRIES = 15

  def initialize(environment_row)
    @row = environment_row
    @workspace = environment_row.integration.workspace
  end

  def receive!(signal, attempt: 0)
    case signal.kind
    when Integrations::PullRequestReviews::REQUESTED then start!(signal, PullRequestReview::TRIGGER_REQUESTED, attempt) if asked?(signal)
    when Integrations::PullRequestReviews::OPENED then start!(signal, PullRequestReview::TRIGGER_AUTOMATIC, attempt) if on_open?(signal)
    when Integrations::PullRequestReviews::PUSHED then pushed!(signal, attempt)
    when Integrations::PullRequestReviews::MERGED then merged!(signal)
    when Integrations::PullRequestReviews::CLOSED then ended!(signal)
    when Integrations::PullRequestReviews::COMMENTED then commented!(signal, attempt)
    end
  end

  # Halon reviews the pull requests it opened too, once they open, as if someone had asked.
  def self.opened_by_halon!(environment_row, repository:, number:)
    new(environment_row).send(:start!, Integrations::PullRequestReviews::Signal.new(kind: Integrations::PullRequestReviews::REQUESTED, repository: repository,
                                                                                     number: number, reference: "#{repository}##{number}:halon"),
                              PullRequestReview::TRIGGER_REQUESTED, 0)
  end

  private

  def asked?(signal) = Integrations::PullRequestReviews.asked?(@row, signal)

  def on_open?(signal) = !signal.draft && @workspace.reviews_on_open?(signal.repository)

  def latest(signal) = PullRequestReview.latest_of(@workspace, signal.repository, signal.number)

  # A new head of a pull request Halon reviewed is reviewed again, the way the last review was asked for, and the fix of
  # each open thread is checked. One never reviewed is reviewed when the workspace reviews every pull request there,
  # since a push is also how a host says a draft became ready.
  def pushed!(signal, attempt)
    previous = latest(signal)
    return start!(signal, PullRequestReview::TRIGGER_AUTOMATIC, attempt) if previous.nil? && on_open?(signal)
    return if previous.nil? || signal.head_sha.blank? || previous.head_sha == signal.head_sha

    previous.open_threads.each { |finding| PullRequestReviewRecheckJob.perform_later(finding.id, previous.head_sha, signal.head_sha) } if attempt.zero?
    start!(signal, previous.trigger, attempt)
  end

  def merged!(signal)
    PullRequestReview.seen.where(workspace_id: @workspace.id).where("lower(repository) = ?", signal.repository.downcase).where(number: signal.number)
                     .find_each { |review| review.merged!(Time.current) }
    ended!(signal)
  end

  # A pull request Halon opened that ended may teach a lesson from what a person did with it.
  def ended!(signal)
    session = CodeAgentSession.opened_pull_request(@workspace, signal.repository, signal.number)
    PullRequestLessonJob.perform_later(session.id) if session
  end

  # A reply on one of Halon's threads is answered. Any other comment that asks Halon to review starts one.
  def commented!(signal, attempt)
    return if Integrations::PullRequestReviews.own?(@row, signal)
    return start!(signal, PullRequestReview::TRIGGER_REQUESTED, attempt) if asked?(signal)
    return unless signal.reply? && signal.person

    finding = thread_finding(signal)
    PullRequestReviewAnswerJob.perform_later(finding.id, signal.to_h.transform_keys(&:to_s)) if finding
  end

  def thread_finding(signal)
    review = latest(signal)
    return unless review

    review.pull_request_findings.find do |finding|
      Integrations::PullRequestReviews.same_thread?(@row.integration, finding.host_comment_id, signal.thread)
    end
  end

  # A review of the pull request's head now, through this connection. A head reviewed already is not reviewed again, and
  # a pull request whose review of an earlier head is still running is tried again once that one ends.
  def start!(signal, trigger, attempt)
    return if reviewed?(signal)

    review = PullRequestReview::Start.call(workspace: @workspace, repository: signal.repository, number: signal.number, trigger: trigger, row: @row)
    waiting = review.live? && signal.head_sha.present? && review.head_sha != signal.head_sha
    return unless waiting && attempt < RETRIES

    PullRequestReviewSignalJob.set(wait: RETRY_WAIT).perform_later(@row.id, signal.to_h.transform_keys(&:to_s), attempt + 1)
  rescue PullRequestReview::Start::Refused, Integrations::Error => error
    Rails.logger.warn({ event: "pull_request_review.start_failed", integration_environment_id: @row.id, repository: signal.repository,
                        number: signal.number, error: error.class.name, message: error.message.truncate(300) }.to_json)
  end

  def reviewed?(signal)
    signal.head_sha.present? && PullRequestReview.seen.where(workspace_id: @workspace.id, number: signal.number, head_sha: signal.head_sha)
                                                 .where("lower(repository) = ?", signal.repository.downcase).where.not(status: PullRequestReview::STATUS_FAILED).exists?
  end
end
