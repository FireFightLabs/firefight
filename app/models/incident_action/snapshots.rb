# frozen_string_literal: true

module IncidentAction::Snapshots
  extend ActiveSupport::Concern

  included do
    include Trackable
    tracked_by IncidentActionUpdate
  end

  def snapshot_attributes
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
end
