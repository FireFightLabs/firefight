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

  PERSON_TYPE = "{ name: string; initials: string; avatarUrl?: string }".freeze

  type :string
  def actor
    event.actor_name
  end

  type :boolean
  def automated
    event.automated?
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

  type "{ label: string; href: string | null }", optional: true
  def subject
    label = event.subject_label
    return nil if label.blank? || person_backed?

    { label: label, href: subject_href }
  end

  type PERSON_TYPE, optional: true
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

  type "{ id: string; description: string; status: string; assignee: #{PERSON_TYPE} | null }", optional: true
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

  # Everything the row needs to render the note, the quote card and the
  # dismissed group, read from what the noting pass stored.
  type MILESTONE_TYPE, optional: true
  def milestone
    return nil unless event.milestone?

    meta = event.metadata.to_h.with_indifferent_access
    {
      kind: meta[:kind],
      statement: meta[:statement].to_s,
      quote: meta[:message_text].presence,
      permalink: meta[:permalink].presence,
      dismissedAt: meta[:dismissed_at].presence,
      dismissedBy: dismissed_by_name(meta)
    }
  end

  type "{ text: string | null; permalink: string | null }", optional: true
  def pin
    return nil unless [ IncidentEvent::MESSAGE_PINNED, IncidentEvent::MESSAGE_UNPINNED ].include?(event.event_type)

    meta = event.metadata.to_h.with_indifferent_access
    { text: meta[:message_text].presence, permalink: meta[:permalink].presence }
  end

  type "{ field: string; before: string; after: string }[]", optional: true
  def changes
    return nil unless event.eventable.is_a?(IncidentUpdate) && event.changed_fields.any?

    current = event.eventable
    previous = current.previous_update

    event.changed_fields.map do |field|
      {
        field: field,
        before: previous&.display_value_for(field).to_s,
        after: current.display_value_for(field).to_s
      }
    end
  end

  type :string, optional: true
  def details
    eventable = event.eventable
    return eventable.message if eventable.respond_to?(:message) && eventable.message.present?

    meta = event.metadata.to_h.with_indifferent_access
    text = meta[:message].presence || meta[:reason].presence
    text.is_a?(String) ? text : nil
  end

  type "{ name: string; mimeType: string | null; slackPermalink: string | null; downloadUrl: string | null; byteSize: number | null }", optional: true
  def file
    return nil unless event.event_type == IncidentEvent::MESSAGE_FILE_SHARED

    meta = event.metadata.to_h.with_indifferent_access
    blob = event.artifact.attached? ? event.artifact.blob : nil

    # The blob describes what downloadUrl actually returns, so it wins over the
    # Slack metadata. Events recorded before that metadata was captured carry
    # only a details key, and would otherwise render with no name or size.
    name = blob&.filename.to_s.presence || meta[:file_name].presence
    permalink = meta[:permalink].presence
    download = artifact_path(event)
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

  # A note whose author has left the workspace still says who dismissed it,
  # and a machine that dismissed one never had a member row to resolve.
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

  def named_person(name, avatar_url)
    return nil if name.blank?

    { name: name, initials: name.split.map { |part| part[0] }.join.upcase, avatarUrl: avatar_url }
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
    end
  end

  def url_helpers
    Rails.application.routes.url_helpers
  end

  def artifact_path(event)
    return nil unless event.artifact.attached?

    Rails.application.routes.url_helpers.rails_blob_path(event.artifact, only_path: true)
  end
end
