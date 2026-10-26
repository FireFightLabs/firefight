# What a person's handling of a pull request Halon opened teaches, read once it merged or closed. One merged as Halon
# wrote it was accepted and teaches nothing, and one Halon or the system closed teaches nothing either. One a person
# changed before merging, or closed, is recorded, and can become one lesson for its repository when the person stated
# why or the same cause showed in an earlier one. The lesson waits for approval like every other, and reviews check it
# only once approved.
class PullRequestLessonService
  def initialize(session)
    @session = session
    @workspace = session.workspace
  end

  # Returns the lesson saved, or nil.
  def learn!
    row = @session.integration_environment
    return nil unless learns? && row && @session.pull_request_number && Integrations::ReviewHost.reads_outcomes?(row.integration)
    return nil unless @session.claim_lesson_read!

    outcome = Integrations::ReviewHost.outcome(row, repository: @session.repository, number: @session.pull_request_number)
    if outcome.state == Integrations::ReviewHost::STATE_OPEN
      @session.release_lesson_read!
      return nil
    end
    return nil unless by_person?(row, outcome)

    handled = handled(row, outcome)
    return nil unless handled

    earlier = CodeAgentSession.handled_before(@session)
    @session.handled!(handled.kind, person: handled.person, summary: summary(handled))
    # A lesson needs a stated reason or a repeated cause, so a close with no word of why and nothing before is left.
    return nil if handled.kind == FirefightAi::PullRequestLessonExtractor::CLOSED && handled.words.blank? && earlier.empty?

    save(extractor.extract(inferable: @session, repository: @session.repository, label: @session.lesson_origin, title: title(row),
                           handled: handled, earlier: earlier.map { |each| earlier_of(each) }))
  rescue FirefightAi::TransientError
    @session.release_lesson_read!
    raise
  rescue Integrations::Error => error
    @session.release_lesson_read!
    Rails.logger.info({ event: "pull_request_lesson.unread", code_agent_session_id: @session.id, error: error.message.truncate(200) }.to_json)
    nil
  end

  private

  def learns? = defined?(FirefightAi) && Entitlements.allows?(@workspace, Entitlements::AI)

  def extractor = FirefightAi::PullRequestLessonExtractor.new(@workspace)

  # Merged or closed by a person, never by Halon itself, a bot or the host.
  def by_person?(row, outcome)
    return false unless outcome.ended_by_person && outcome.ended_by.present?

    !Integrations::PullRequestReviews.identity(row).matches?(outcome.ended_by)
  rescue Integrations::Error
    outcome.ended_by_person
  end

  # What the person did, or nil for a pull request merged as Halon wrote it.
  def handled(row, outcome)
    person = outcome.ended_by
    if outcome.state == Integrations::ReviewHost::STATE_MERGED
      edits = outcome.commits.each_with_index.reject { |commit, _index| commit.merge || commit.email.to_s.casecmp?(CodeAgentSession::COMMIT_EMAIL) }
      return nil if edits.empty?

      first = edits.first.last
      from = outcome.commits[first - 1].sha if first.positive?
      changes = from ? Integrations::ReviewHost.changes_between(row, repository: @session.repository, from: from, to: outcome.commits.last.sha) : ""
      words = [ *edits.map { |commit, _index| "Commit by #{commit.author}: #{commit.message.strip}" }, *people_comments(outcome) ].join("\n")
      FirefightAi::PullRequestLessonExtractor::Handled.new(kind: FirefightAi::PullRequestLessonExtractor::EDITED, person: person, words: words, changes: changes)
    else
      said = [ ("The reason given for closing it: #{outcome.reason}" if outcome.reason), *people_comments(outcome) ].compact.join("\n")
      FirefightAi::PullRequestLessonExtractor::Handled.new(kind: FirefightAi::PullRequestLessonExtractor::CLOSED, person: person, words: said)
    end
  end

  def people_comments(outcome)
    outcome.comments.select(&:person).map { |comment| "Comment by #{comment.author}: #{comment.body.strip}" }
  end

  def summary(handled) = [ handled.words, handled.changes.to_s.first(300) ].compact_blank.join("\n").squish

  def title(row)
    Integrations::ReviewHost.pull_request(row, repository: @session.repository, number: @session.pull_request_number).title
  rescue Integrations::Error
    ""
  end

  def earlier_of(session)
    FirefightAi::PullRequestLessonExtractor::Earlier.new(label: session.lesson_origin, kind: session.outcome_kind, summary: session.outcome_summary.to_s)
  end

  # Saved as a memory taught by the pull request, so it waits on the Lessons tab for approval. One the workspace holds
  # already, or one a person rejected before, is not saved again.
  def save(result)
    return nil unless result

    learned = Chat::Memory.learn!(@workspace, text: result.lesson, subject: @session.lesson_subject, source: @session,
                                              judge: FirefightAi::MemoryJudge.new(@workspace, inferable: @session))
    learned.memory if learned.outcome == Chat::Memory::LEARNED_SAVED
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
