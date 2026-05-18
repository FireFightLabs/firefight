# frozen_string_literal: true

module IncidentAction::Snapshots
  extend ActiveSupport::Concern

  UPDATE_TYPE_MAP = {
    IncidentEvent::ACTION_CREATED => IncidentActionUpdate::CREATED,
    IncidentEvent::ACTION_PICKED_UP => IncidentActionUpdate::PICKED_UP,
    IncidentEvent::ACTION_COMPLETED => IncidentActionUpdate::COMPLETED
  }.freeze

  def build_snapshot_attributes
    {
      incident_action: self,
      incident: incident,
      created_by: created_by,
      assignee: assignee,
      action_type: action_type,
      description: description,
      status: status,
      message_ts: message_ts,
      platform_data: platform_data,
      deleted_at: deleted_at
    }
  end

  def record_change!(event_type, actor:)
    before_tracked = trackable_snapshot
    yield
    reload
    after_tracked = trackable_snapshot

    changed_fields = before_tracked.keys.select { |key| before_tracked[key] != after_tracked[key] }

    update = IncidentActionUpdate.create!(
      **build_snapshot_attributes,
      update_type: UPDATE_TYPE_MAP.fetch(event_type),
      actor: actor,
      changed_fields: changed_fields.map(&:to_s)
    )

    incident.incident_events.create!(
      event_type: event_type,
      user: actor,
      eventable: update
    )
  end

  def create_initial_update!(actor:)
    update = IncidentActionUpdate.create!(
      **build_snapshot_attributes,
      update_type: IncidentActionUpdate::CREATED,
      actor: actor,
      changed_fields: []
    )

    incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_CREATED,
      user: actor,
      eventable: update
    )
  end

  private

  def trackable_snapshot
    {
      assignee: assignee_id,
      status: status,
      description: description,
      deleted_at: deleted_at
    }
  end
end
