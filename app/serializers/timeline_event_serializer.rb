class TimelineEventSerializer < BaseSerializer
  object_as :event

  type :string
  def id
    event.id
  end

  EVENT_TYPE_UNION = IncidentEvent::EVENT_TYPES.map(&:inspect).join(" | ")

  type EVENT_TYPE_UNION
  def event_type
    event.event_type
  end

  # Mirrors ActorCompactSerializer. The generator only resolves a has_one, and person
  # is built by hand for people with no membership row.
  ACTOR_TYPE = "{ name: string; avatarUrl?: string; kind: #{ActorCompactSerializer::KIND_UNION} }"

  type :string
  def actor
    event.actor_name
  end

  type :boolean
  def automated
    event.automated?
  end

  # Marks a machine as one. Absent when nobody acted, which is what an automated entry looks like.
  type ActorCompactSerializer::KIND_UNION, optional: true
  def actor_kind
    event.actor&.actor_kind
  end

  type :string, optional: true
  def actor_avatar_url
    actor = event.actor
    return nil unless actor.respond_to?(:user)

    actor.user&.avatar_url
  end

  type :string
  def created_at
    event.created_at.utc.iso8601
  end

  type :string
  def description
    event.description_stem
  end

  # external says href is the page's own address in another tool, such as a page in an on-call tool, opened in a new tab.
  type "{ label: string; href: string | null; external: boolean }", optional: true
  def subject
    label = event.subject_label
    return nil if label.blank? || person_backed?

    page_url = page_address
    { label: label, href: page_url || subject_href, external: page_url.present? }
  end

  type ACTOR_TYPE, optional: true
  def person
    return nil unless person_backed?

    meta = event.metadata.to_h.with_indifferent_access
    case event.event_type
    when IncidentEvent::LEAD_ASSIGNED
      member_person(event.eventable&.lead)
    when IncidentEvent::ROLE_ASSIGNED
      member_person(event.references&.member(meta[:member_id]))
    when IncidentEvent::INCIDENT_ESCALATED, IncidentEvent::ESCALATION_NUDGED
      member_person(event.references&.member(meta[:escalated_to_member_id])) ||
        named_person(meta[:escalated_to_name], meta[:escalated_to_avatar_url])
    when IncidentEvent::MILESTONE_NOTED
      member_person(event.references&.member(meta[:member_id])) ||
        named_person(meta[:member_name], meta[:member_avatar_url])
    end
  end

  type "{ id: string; description: string; status: string; assignee: #{ACTOR_TYPE} | null }", optional: true
  def action
    update = event.eventable
    return nil unless update.is_a?(IncidentActionUpdate)

    {
      id: update.incident_action_id,
      description: update.description,
      status: update.status,
      assignee: member_person(update.assignee)
    }
  end

  MILESTONE_KIND_UNION = IncidentEvent::MILESTONE_KINDS.map(&:inspect).join(" | ")
  MILESTONE_TYPE = "{ kind: #{MILESTONE_KIND_UNION}; statement: string; " \
                   "quote: string | null; permalink: string | null; " \
                   "dismissedAt: string | null; dismissedBy: string | null }".freeze

  type MILESTONE_TYPE, optional: true
  def milestone
    return nil unless event.milestone?

    meta = event.metadata.to_h.with_indifferent_access
    {
      kind: meta[:kind],
      statement: meta[:statement].to_s,
      quote: quote,
      permalink: meta[:permalink].presence,
      dismissedAt: meta[:dismissed_at].presence,
      dismissedBy: dismissed_by_name(meta)
    }
  end

  type "{ text: string | null; permalink: string | null }", optional: true
  def pin
    return nil unless [ IncidentEvent::MESSAGE_PINNED, IncidentEvent::MESSAGE_UNPINNED ].include?(event.event_type)

    meta = event.metadata.to_h.with_indifferent_access
    { text: quote, permalink: meta[:permalink].presence }
  end

  type "{ field: string; label: string; kind: #{IncidentUpdate::CHANGE_KINDS.map(&:inspect).join(" | ")}; before: string | null; after: string | null }[]", optional: true
  def changes
    return nil unless event.eventable.is_a?(IncidentUpdate) && event.changed_fields.any?

    current = event.eventable
    definitions = event.references&.field_definitions || {}
    current.changes_since(current.previous_update, field_definitions: definitions).map(&:to_h)
  end

  # Written as markdown, so the page renders its lists and links. Details stays plain text.
  type :string, optional: true
  def update_message
    event.update_message
  end

  # What a fix step did, with the link to what it produced split out where the sentence names it.
  type "{ title: string; result: string | null; link: { before: string; label: string; href: string; after: string } | null }", optional: true
  def fix_step
    step = event.fix_step
    return nil unless step

    { title: step.title, result: step.result, link: step.link&.to_h }
  end

  # The short answer a channel reads first, with the full answer behind it. The run's answer is read from the run when
  # the page handed it in, so an answer noted before the short one was kept still shows it.
  type "{ headline: string; sureness: string | null; whatIsWrong: string | null; suggestedFix: string | null; full: string | null }",
       optional: true
  def answer
    answer = event.investigation_answer(options.fetch(:answers, {})[event.id])
    return nil unless answer

    { headline: answer.headline, sureness: answer.sureness, whatIsWrong: answer.what_is_wrong,
      suggestedFix: answer.suggested_fix, full: answer.full.presence }
  end

  type :string, optional: true
  def details
    return nil if update_message
    return nil if fix_step || answer

    eventable = event.eventable
    return eventable.message if eventable.respond_to?(:message) && eventable.message.present?

    started = options.fetch(:started_questions, {})[event.id]
    return started if started

    meta = event.metadata.to_h.with_indifferent_access
    text = meta[:message].presence || meta[:reason].presence
    text.is_a?(String) ? text : nil
  end

  type "{ name: string; mimeType: string | null; slackPermalink: string | null; downloadUrl: string | null; byteSize: number | null }", optional: true
  def file
    return nil unless event.event_type == IncidentEvent::MESSAGE_FILE_SHARED

    meta = event.metadata.to_h.with_indifferent_access
    archived = event.archived_file
    blob = archived&.blob

    # The blob describes what downloadUrl returns, so it wins. Older events carry only
    # a details key and would render with no name or size.
    name = blob&.filename.to_s.presence || meta[:file_name].presence
    permalink = meta[:permalink].presence
    download = archived && url_helpers.rails_blob_path(archived, only_path: true)
    return nil if name.blank? && download.blank? && permalink.blank?

    {
      name: name.to_s,
      mimeType: blob&.content_type.presence || meta[:mime_type].presence,
      slackPermalink: permalink,
      downloadUrl: download,
      byteSize: blob&.byte_size || meta[:byte_size]
    }
  end

  private

  PERSON_EVENTS = [
    IncidentEvent::LEAD_ASSIGNED, IncidentEvent::ROLE_ASSIGNED,
    IncidentEvent::INCIDENT_ESCALATED, IncidentEvent::ESCALATION_NUDGED,
    IncidentEvent::MILESTONE_NOTED
  ].freeze

  # The quote as markdown, from the platform's own reading of its text, which the controller hands in as quotes.
  def quote
    text = event.quoted_message
    text && options.fetch(:quotes, {}).fetch(text, text)
  end

  # The author may have left the workspace, and a machine never had a member row.
  def dismissed_by_name(meta)
    return nil if meta[:dismissed_at].blank?

    event.references&.member(meta[:dismissed_by_member_id])&.display_name || meta[:dismissed_by_name].presence
  end

  def person_backed?
    PERSON_EVENTS.include?(event.event_type)
  end

  def member_person(member)
    return nil unless member

    ActorCompactSerializer.one(member)
  end

  # Someone with no membership row, still a person, so the chip renders one.
  def named_person(name, avatar_url)
    return nil if name.blank?

    {
      name: name,
      avatarUrl: avatar_url,
      kind: Ability::Principal::KIND_USER
    }
  end

  def subject_href
    meta = event.metadata.to_h.with_indifferent_access
    references = event.references
    return nil unless references

    case event.event_type
    when IncidentEvent::RUNBOOK_ATTACHED
      runbook = references.runbook(meta[:runbook_id])
      runbook && runbook.deleted_at.nil? ? url_helpers.settings_runbooks_path(Runbook::QUERY_PARAM => runbook.id) : nil
    when IncidentEvent::RELATIONSHIP_CREATED, IncidentEvent::MARKED_DUPLICATE
      related = references.incident(meta[:related_incident_id])
      related && url_helpers.incident_path(related)
    when IncidentEvent::MERGED_INTO
      canonical = references.incident(meta[:canonical_incident_id])
      canonical && url_helpers.incident_path(canonical)
    when *IncidentEvent::INVESTIGATION_EVENTS, *IncidentEvent::FIX_EVENTS
      url_helpers.incident_path(event.incident_id, Investigation::QUERY_PARAM => meta[:investigation_id])
    end
  end

  def page_address
    return nil unless IncidentEvent::PAGE_EVENTS.include?(event.event_type)

    url = event.metadata.to_h["url"].to_s
    url.start_with?("https://") ? url : nil
  end

  def url_helpers
    Rails.application.routes.url_helpers
  end
end
