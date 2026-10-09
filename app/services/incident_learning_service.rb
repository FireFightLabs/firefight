# What an ended incident taught about the setup, written down for the next incident to start from. At resolve it saves
# the lessons unconfirmed and asks the channel to confirm them. When a postmortem is completed it reads it against what
# was saved, confirming what it agrees with and correcting what it contradicts, and asks the channel about anything new.
# A postmortem never overrules a person. One that contradicts what a person confirmed marks it disputed for a person.
class IncidentLearningService
  TRANSCRIPT_MESSAGES = 300
  # How much of what the workspace already holds the extractor reads, the most recently changed first.
  REMEMBERED_LIMIT = 60

  def initialize(workspace)
    @workspace = workspace
  end

  # Returns the memories it saved. A workspace whose plan does not include AI, or an incident that taught nothing, gets no memories
  # and no message.
  def learn!(incident, postmortem: nil)
    return [] unless learns?

    known = incident_memories(incident)
    result = extractor.extract(incident, sources: sources(incident, postmortem), subjects: subjects(incident).keys,
                                         known: known.map { |memory| FirefightAi::LessonExtractor::Known.new(id: memory.id, text: memory.text) },
                                         remembered: remembered(incident, known))
    apply_verdicts(result.verdicts, known, postmortem) if postmortem
    saved = save(incident, result.lessons)
    posts.post!(incident, saved, kind: postmortem ? Chat::MemoryPost::KIND_POSTMORTEM : Chat::MemoryPost::KIND_INCIDENT)
    saved
  end

  # An answer marked wrong after its incident ended. Only the lesson about the mistake is asked for, read against every
  # lesson the incident already has, rejected ones too, so nothing the channel saw is posted again. A completed
  # postmortem is read too, since it is the best account of what really happened.
  def learn_from_mistake!(incident)
    return [] unless learns?

    postmortem = incident.postmortem if incident.postmortem&.completed?
    known = incident_memories(incident, rejected: true)
    result = extractor.extract(incident, sources: sources(incident, postmortem), subjects: subjects(incident).keys, only_mistakes: true,
                                         known: known.map { |memory| FirefightAi::LessonExtractor::Known.new(id: memory.id, text: memory.text) },
                                         remembered: remembered(incident, known))
    saved = save(incident, result.lessons)
    posts.post!(incident, saved, kind: Chat::MemoryPost::KIND_INCIDENT)
    saved
  end

  private

  def learns?
    defined?(FirefightAi) && Entitlements.allows?(@workspace, Entitlements::AI)
  end

  def extractor = @extractor ||= FirefightAi::LessonExtractor.new(@workspace)

  def posts = @posts ||= MemoryPostService.new(@workspace)

  def sources(incident, postmortem)
    source = FirefightAi::LessonExtractor::Source
    [
      source.new(title: "What the investigation found", text: findings(incident)),
      source.new(title: "What Halon got wrong", text: mistakes(incident)),
      source.new(title: "Summary", text: FirefightAi::IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)&.content.to_s),
      source.new(title: "Channel transcript (chronological)", text: transcript(incident)),
      (source.new(title: "The postmortem", text: ActionView::Base.full_sanitizer.sanitize(postmortem.html_content).to_s.squish) if postmortem)
    ].compact
  end

  def answers(incident)
    @answers ||= incident.investigations.seen.order(:created_at)
                         .includes(finding: [ :winning_hypothesis, { remediation_plan: :undo_plan } ]).filter_map(&:finding)
  end

  # What the team stood by. An answer they marked wrong is never read as a fact, only as a mistake below.
  def findings(incident)
    answers(incident).reject { |finding| finding.outcome == Investigation::Finding::OUTCOME_WRONG || finding.summary.blank? }
                     .map { |finding| "- #{finding.summary}#{" (#{finding.outcome} by the team)" if finding.outcome}" }.join("\n")
  end

  # An answer the team marked wrong, and a fix that had to be undone, so a lesson can say what really happened and what
  # misled Halon, for the next incident not to repeat it.
  def mistakes(incident)
    answers(incident).flat_map do |finding|
      fix = finding.remediation_plan
      wrong = finding.outcome == Investigation::Finding::OUTCOME_WRONG && finding.summary.present?
      undone = fix&.undo_plan && [ Investigation::RemediationPlan::STATUS_APPLIED, Investigation::RemediationPlan::STATUS_PARTLY_APPLIED ].include?(fix.undo_plan.status)
      [
        ("- Halon's answer, which the team marked wrong: #{finding.summary}#{" The cause Halon gave: #{finding.winning_hypothesis.assertion}" if finding.winning_hypothesis}" if wrong),
        ("- The fix Halon proposed (#{fix.summary}) was applied and then undone, which can mean it was wrong or only a temporary measure." if undone)
      ].compact
    end.join("\n")
  end

  def transcript(incident)
    incident.incident_transcript_messages.kept.includes(workspace_membership: :user).order(:posted_at).last(TRANSCRIPT_MESSAGES).map do |message|
      "#{message.workspace_membership&.user&.name || message.platform_user_id}: #{message.content}"
    end.join("\n")
  end

  # The names a lesson may be about, each to what it names.
  def subjects(incident)
    @subjects ||= Chat::Memory.subjects_for(incident).index_by(&:name)
  end

  def incident_memories(incident, rejected: false)
    scope = Chat::Memory.where(workspace: @workspace, source: incident).includes(:confirmed_by, :rejected_by).order(:created_at)
    rejected ? scope.to_a : scope.in_use.to_a
  end

  # What the workspace already holds about what the incident touches, and about the whole workspace, rejected ones too,
  # so the extractor never learns any of it again in other words. The incident's own lessons are read as known instead.
  def remembered(incident, known)
    subjects = Chat::Memory.subjects_for(incident)
    about = subjects.group_by { |subject| subject.class.name }.map { |type, found| Chat::Memory.where(subject_type: type, subject_id: found.map(&:id)) }
    scope = Chat::Memory.where(workspace: @workspace).where.not(id: known.map(&:id))
    held = about.inject(scope.where(subject_id: nil)) { |union, part| union.or(scope.merge(part)) }
    held.order(updated_at: :desc).limit(REMEMBERED_LIMIT).map do |memory|
      FirefightAi::LessonExtractor::Remembered.new(text: memory.text, rejected: memory.state == Chat::Memory::STATE_REJECTED)
    end
  end

  # Only new lessons are shown. One already known, or rejected before, is not learned again.
  # A lesson that contradicts a memory about the same thing disputes it, and the channel is asked which is right.
  def save(incident, lessons)
    judge = FirefightAi::MemoryJudge.new(@workspace, inferable: incident)
    lessons.filter_map do |lesson|
      learned = Chat::Memory.learn!(@workspace, text: lesson.fact, subject: subjects(incident)[lesson.about], source: incident,
                                                judge: judge, contradiction: "#{incident.identifier} showed \"#{lesson.fact}\".")
      learned.contradicted.each { |memory| posts.post!(incident, [ memory ], kind: Chat::MemoryPost::KIND_DISPUTED) }
      learned.memory if learned.outcome == Chat::Memory::LEARNED_SAVED
    rescue ActiveRecord::RecordInvalid
      # One holding a secret is dropped rather than failing the others.
      nil
    end
  end

  # A completed postmortem confirms what Halon learned and it agrees with, credited to whoever completed it when that was
  # a person. What it contradicts is rejected and replaced when only Halon or a postmortem stood behind it, and marked
  # disputed with the correction when a person confirmed it, for a person to decide.
  def apply_verdicts(verdicts, known, postmortem)
    completer = postmortem.completed_by
    person = completer if completer.is_a?(WorkspaceMembership)
    memories = known.index_by(&:id)
    verdicts.each do |verdict|
      memory = memories[verdict.memory_id]
      if verdict.verdict == FirefightAi::Schemas::Lessons::AGREES
        memory.confirm_from_postmortem!(postmortem, by: person)
      elsif memory.confirmed_by_id
        memory.dispute!([ "The #{postmortem.incident.identifier} postmortem says otherwise", ("and gives this instead. #{verdict.correction}" if verdict.correction) ].compact.join(" "))
      else
        memory.reject!(by: person, reason: "The #{postmortem.incident.identifier} postmortem says otherwise", correction: verdict.correction, postmortem: postmortem)
      end
    end
  end
end
