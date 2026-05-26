module Incident::Snapshots
  extend ActiveSupport::Concern

  included do
    include Trackable
    tracked_by IncidentUpdate, diff_aliases: {
      incident_status:   :status,
      incident_severity: :severity,
      incident_type:     :type,
      lead:              :lead
    }
  end

  def snapshot_attributes
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
end
