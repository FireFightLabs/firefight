# frozen_string_literal: true

# Incident::Snapshots - Event snapshot generation and change tracking
#
# Provides full snapshot capabilities for incident events, capturing complete
# before/after states with denormalized data for timeline reconstruction.
#
# Uses before/after snapshots instead of diffs to:
# - View incident state at any point in time without reconstruction
# - Handle renamed/deleted statuses/severities via denormalization
# - Easily detect what changed by comparing snapshots
#
module Incident::Snapshots
  extend ActiveSupport::Concern

  # Snapshot for events (denormalized data)
  def snapshot
    {
      identifier: identifier,
      name: name,
      summary: summary,
      severity: incident_severity.as_json(only: [ :id, :name, :slug, :rank, :color ]),
      status: incident_status.as_json(only: [ :id, :name, :slug, :category ]),
      lead: lead&.as_json(only: [ :id ], methods: [ :display_name, :email ]),
      declared_by: declared_by.as_json(only: [ :id ], methods: [ :display_name ]),
      declared_at: declared_at,
      resolved_at: resolved_at
    }
  end

  # Record change with full snapshots
  def record_change!(event_type, details: nil, changed_by: nil)
    before_snapshot = snapshot
    yield # Perform the change
    after_snapshot = reload.snapshot

    # Detect changed fields
    changed_fields = before_snapshot.keys.select do |key|
      before_snapshot[key] != after_snapshot[key]
    end

    incident_events.create!(
      event_type: event_type,
      user: changed_by,
      metadata: {
        schema_version: 1,
        before: before_snapshot,
        after: after_snapshot,
        changed_fields: changed_fields,
        details: details
      }
    )
  end
end
