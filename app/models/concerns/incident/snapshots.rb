# frozen_string_literal: true

module Incident::Snapshots
  extend ActiveSupport::Concern

  UPDATE_TYPE_MAP = {
    IncidentEvent::INCIDENT_CREATED => IncidentUpdate::CREATED,
    IncidentEvent::INCIDENT_UPDATED => IncidentUpdate::UPDATED,
    IncidentEvent::INCIDENT_RESOLVED => IncidentUpdate::CLOSED,
    IncidentEvent::INCIDENT_REOPENED => IncidentUpdate::REOPENED,
    IncidentEvent::LEAD_ASSIGNED => IncidentUpdate::LEAD_ASSIGNED
  }.freeze

  def build_snapshot_attributes
    {
      incident: self,
      workspace_id: workspace_id,
      incident_status: incident_status,
      incident_severity: incident_severity,
      incident_type: incident_type,
      declared_by: declared_by,
      lead: lead,
      sequence_number: sequence_number,
      identifier: identifier,
      name: name,
      summary: summary,
      is_private: is_private,
      channel_id: channel_id,
      channel_name: channel_name,
      initial_message_ts: initial_message_ts,
      announcement_message_ts: announcement_message_ts,
      platform_data: platform_data,
      custom_fields: custom_fields,
      detected_at: detected_at,
      declared_at: declared_at,
      resolved_at: resolved_at,
      channel_archived_at: channel_archived_at,
      channel_archived_by: channel_archived_by,
      next_update_at: next_update_at,
      deleted_at: deleted_at
    }
  end

  def record_change!(event_type, details: nil, changed_by: nil, message: nil)
    before_tracked = trackable_snapshot
    yield
    reload
    after_tracked = trackable_snapshot

    changed_fields = before_tracked.keys.select { |key| before_tracked[key] != after_tracked[key] }

    update = IncidentUpdate.create!(
      **build_snapshot_attributes,
      update_type: UPDATE_TYPE_MAP.fetch(event_type),
      created_by: changed_by,
      message: message,
      changed_fields: changed_fields.map(&:to_s)
    )

    incident_events.create!(
      event_type: event_type,
      user: changed_by,
      eventable: update,
      metadata: details ? { details: details } : {}
    )
  end

  def create_initial_update!(created_by:)
    update = IncidentUpdate.create!(
      **build_snapshot_attributes,
      update_type: IncidentUpdate::CREATED,
      created_by: created_by,
      changed_fields: []
    )

    incident_events.create!(
      event_type: IncidentEvent::INCIDENT_CREATED,
      user: created_by,
      eventable: update
    )
  end

  private

  def trackable_snapshot
    {
      status: incident_status_id,
      severity: incident_severity_id,
      type: incident_type_id,
      lead: lead&.id,
      name: name,
      summary: summary,
      is_private: is_private,
      detected_at: detected_at,
      declared_at: declared_at,
      resolved_at: resolved_at
    }
  end
end
