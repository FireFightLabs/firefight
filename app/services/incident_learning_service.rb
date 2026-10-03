# What an ended incident taught about the setup, written down for the next incident to start from. At resolve it saves
# the lessons unconfirmed and asks the channel to confirm them. When a postmortem is completed it reads it against what
# was saved, confirming what it agrees with and correcting what it contradicts, and posts nothing.
class IncidentLearningService
  TRANSCRIPT_MESSAGES = 300

  def initialize(workspace)
    @workspace = workspace
  end

  # Returns the memories it saved. A workspace without the agent, or an incident that taught nothing, gets no memories
  # and no message.
  def learn!(incident, postmortem: nil)
    return [] unless learns?

    known = incident_memories(incident)
    result = extractor.extract(incident, sources: sources(incident, postmortem), subjects: subjects(incident).keys,
                                         known: known.map { |memory| FirefightAi::LessonExtractor::Known.new(id: memory.id, text: memory.text) })
    apply_verdicts(result.verdicts, known, postmortem) if postmortem
    saved = save(incident, result.lessons)
    announce(incident, saved) if saved.any? && postmortem.nil?
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
                                         known: known.map { |memory| FirefightAi::LessonExtractor::Known.new(id: memory.id, text: memory.text) })
    saved = save(incident, result.lessons)
    announce(incident, saved) if saved.any?
    saved
  end

  # Someone in the channel confirming or rejecting one of the incident's lessons, then the message redrawn to show it.
  # Returns false when the lesson is not the incident's.
  def decide!(incident_id:, memory_id:, member:, confirmed:, channel_id:, message_id:)
    incident = @workspace.incidents.find_by(id: incident_id)
    memory = Chat::Memory.where(workspace: @workspace, source: incident).find_by(id: memory_id) if incident
    return false unless memory

    if confirmed
      memory.confirm!(by: member)
    else
      memory.reject!(by: member, reason: "Marked not right in #{incident.identifier}")
    end
    redraw(incident, channel_id: channel_id, message_id: message_id)
    true
  end

  private

  def redraw(incident, channel_id:, message_id:)
    @workspace.adapter.update_learned_memories(channel_id: channel_id, message_id: message_id, incident_id: incident.id,
                                               incident_identifier: incident.identifier, memories: shown(incident_memories(incident, rejected: true)))
  end

  def learns?
    defined?(FirefightAi) && FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE) && Entitlements.allows?(@workspace, Entitlements::AI)
  end

  def extractor = @extractor ||= FirefightAi::LessonExtractor.new(@workspace)

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

  # Only new lessons are shown. One already known, or rejected before, is not learned again.
  def save(incident, lessons)
    lessons.filter_map do |lesson|
      learned = Chat::Memory.learn!(@workspace, text: lesson.fact, subject: subjects(incident)[lesson.about], source: incident)
      learned.memory if learned.outcome == Chat::Memory::LEARNED_SAVED
    rescue ActiveRecord::RecordInvalid
      # One holding a secret is dropped rather than failing the others.
      nil
    end
  end

  # A postmortem is a person's considered account, so it confirms what it agrees with and corrects what it contradicts.
  def apply_verdicts(verdicts, known, postmortem)
    author = postmortem.generated_by if postmortem.generated_by.is_a?(WorkspaceMembership)
    memories = known.index_by(&:id)
    verdicts.each do |verdict|
      memory = memories[verdict.memory_id]
      if verdict.verdict == FirefightAi::Schemas::Lessons::AGREES
        memory.confirm!(by: author, reason: "The postmortem agrees")
      else
        memory.reject!(by: author, reason: "The postmortem says otherwise", correction: verdict.correction)
      end
    end
  end

  # A channel archived since the incident ended cannot be posted in, so the lessons wait on the Memory page instead.
  def announce(incident, saved)
    return if incident.channel_id.blank?

    @workspace.adapter.post_learned_memories(channel_id: incident.channel_id, incident_id: incident.id,
                                             incident_identifier: incident.identifier, memories: shown(saved))
  rescue AdapterError::IsArchived, AdapterError::NotFound, AdapterError::NotInChannel => error
    Rails.logger.info({ event: "incident_learning.not_posted", incident_id: incident.id, error: error.class.name }.to_json)
  end

  def shown(memories)
    memories.map do |memory|
      LearnedMemory.new(id: memory.id, text: memory.text, about: memory.about, state: memory.state,
                        decided_by: (memory.rejected_by || memory.confirmed_by)&.display_name)
    end
  end

  # What a platform message shows of a lesson, so the adapter never reads a memory record.
  LearnedMemory = Data.define(:id, :text, :about, :state, :decided_by)
end
