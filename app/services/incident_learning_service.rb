# What an ended incident taught about the setup, written down for the next incident to start from. At resolve it saves
# the lessons unconfirmed and asks the channel to confirm them. When a postmortem is completed it reads it against what
# was saved, confirming what it agrees with and correcting what it contradicts, quietly.
class IncidentLearningService
  TRANSCRIPT_MESSAGES = 300

  def initialize(workspace)
    @workspace = workspace
  end

  # Returns the memories it saved. Learning is decoration on an ended incident, so a workspace without the agent, or
  # with nothing learned, gets nothing and no message.
  def learn!(incident, postmortem: nil)
    return [] unless learns?

    known = incident_memories(incident)
    result = extractor.extract(incident, sources: sources(incident, postmortem), subjects: subjects(incident).keys,
                                         known: known.map { |memory| FirefightAi::LessonExtractor::Known.new(id: memory.id, text: memory.text) })
    apply_verdicts(result.verdicts, known, postmortem) if postmortem
    saved = save(incident, result.lessons, known)
    announce(incident, saved) if saved.any? && postmortem.nil?
    saved
  end

  # Redraws the channel message after someone decides on one of its lessons.
  def redraw(incident, channel_id:, message_id:)
    @workspace.adapter.update_learned_memories(channel_id: channel_id, message_id: message_id, incident_id: incident.id,
                                               incident_identifier: incident.identifier, memories: shown(incident_memories(incident, rejected: true)))
  end

  private

  def learns?
    defined?(FirefightAi) && FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE) && Entitlements.allows?(@workspace, Entitlements::AI)
  end

  def extractor = @extractor ||= FirefightAi::LessonExtractor.new(@workspace)

  def sources(incident, postmortem)
    source = FirefightAi::LessonExtractor::Source
    [
      source.new(title: "What the investigation found", text: findings(incident)),
      source.new(title: "Summary", text: FirefightAi::IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)&.content.to_s),
      source.new(title: "Channel transcript (chronological)", text: transcript(incident)),
      (source.new(title: "The postmortem", text: ActionView::Base.full_sanitizer.sanitize(postmortem.html_content).to_s.squish) if postmortem)
    ].compact
  end

  # A finding people marked wrong teaches nothing.
  def findings(incident)
    incident.investigations.includes(:finding).filter_map(&:finding)
            .reject { |finding| finding.outcome == Investigation::Finding::OUTCOME_WRONG || finding.summary.blank? }
            .map { |finding| "- #{finding.summary}#{" (#{finding.outcome} by the team)" if finding.outcome}" }.join("\n")
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

  def save(incident, lessons, known)
    lessons.filter_map do |lesson|
      next if known.any? { |memory| memory.text.casecmp?(lesson.fact) }

      # A lesson that fails validation, such as one holding a secret, is dropped rather than failing the others.
      memory = Chat::Memory.create(workspace: @workspace, text: lesson.fact, state: Chat::Memory::STATE_UNCONFIRMED,
                                   subject: subjects(incident)[lesson.about], source: incident)
      memory if memory.persisted?
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

  def announce(incident, saved)
    return if incident.channel_id.blank?

    @workspace.adapter.post_learned_memories(channel_id: incident.channel_id, incident_id: incident.id,
                                             incident_identifier: incident.identifier, memories: shown(saved))
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
