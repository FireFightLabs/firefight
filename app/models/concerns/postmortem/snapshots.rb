module Postmortem::Snapshots
  extend ActiveSupport::Concern

  UPDATE_TYPE_MAP = {
    IncidentEvent::POSTMORTEM_GENERATED => PostmortemUpdate::GENERATED,
    IncidentEvent::POSTMORTEM_EDITED => PostmortemUpdate::EDITED
  }.freeze

  def build_snapshot_attributes
    {
      postmortem: self,
      incident: incident,
      title: title,
      summary: summary,
      content: content,
      status: status,
      model_id: model_id
    }
  end

  def create_initial_update!(edited_by:)
    update = PostmortemUpdate.create!(
      **build_snapshot_attributes,
      update_type: PostmortemUpdate::GENERATED,
      edited_by: edited_by,
      changed_sections: []
    )

    incident.incident_events.create!(
      event_type: IncidentEvent::POSTMORTEM_GENERATED,
      user: edited_by,
      eventable: update
    )
  end

  def update_content!(html_content, edited_by:)
    record_change!(IncidentEvent::POSTMORTEM_EDITED, edited_by: edited_by) do
      update!(content: content.merge("html" => html_content))
    end
  end

  def update_status!(new_status, edited_by:)
    record_change!(IncidentEvent::POSTMORTEM_EDITED, edited_by: edited_by) do
      update!(status: new_status)
    end
  end

  def record_change!(event_type, edited_by:)
    before_tracked = trackable_snapshot
    yield
    reload
    after_tracked = trackable_snapshot

    changed = before_tracked.keys.select { |key| before_tracked[key] != after_tracked[key] }

    update = PostmortemUpdate.create!(
      **build_snapshot_attributes,
      update_type: UPDATE_TYPE_MAP.fetch(event_type, PostmortemUpdate::EDITED),
      edited_by: edited_by,
      changed_sections: changed.map(&:to_s)
    )

    incident.incident_events.create!(
      event_type: event_type,
      user: edited_by,
      eventable: update
    )
  end

  private

  def trackable_snapshot
    {
      title: title,
      summary: summary,
      content: content,
      status: status
    }
  end
end
