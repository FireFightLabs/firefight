# frozen_string_literal: true

# Trackable lets a model record every meaningful state change as an immutable
# snapshot + IncidentEvent pair. Include it on a "live" model and declare the
# matching Recordable + per-model snapshot_attributes hash.
#
#   class Incident
#     include Trackable
#     tracked_by IncidentUpdate
#
#     def snapshot_attributes
#       { incident: self, workspace_id:, incident_status:, ... }
#     end
#   end
#
# Then any caller can do:
#
#   incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: member) do
#     incident.update!(incident_status: resolved_status)
#   end
#
# which produces (atomically) a Recordable row with the full snapshot + diff,
# then an IncidentEvent linking the two. IncidentEvent's commit hook fires
# the domain-event bus.
#
# For "this just got created" moments, pass no block — the diff is empty:
#
#   incident.record_change!(IncidentEvent::INCIDENT_CREATED, by: declared_by)
module Trackable
  extend ActiveSupport::Concern

  class_methods do
    # @param recordable_class [Class] the Recordable model that stores snapshots
    # @param incident_via [Symbol] method returning the parent Incident
    #   (default :itself when self == Incident, :incident otherwise)
    # @param diff_aliases [Hash] optional snapshot_attributes-key -> public-name
    #   rename map used only for the changed_fields contract. snapshot_attributes
    #   keys stay as the real AR association names (e.g. :incident_status),
    #   but changed_fields and event.changed?(:foo) speak the public name (:status).
    def tracked_by(recordable_class, incident_via: nil, diff_aliases: {})
      @trackable_recordable   = recordable_class
      @trackable_incident_via = incident_via || (name == "Incident" ? :itself : :incident)
      @trackable_diff_aliases = diff_aliases.transform_keys(&:to_sym)
    end

    def trackable_recordable
      @trackable_recordable
    end

    def trackable_incident_via
      @trackable_incident_via
    end

    def trackable_diff_aliases
      @trackable_diff_aliases || {}
    end
  end

  def record_change!(event_type, by:, message: nil, metadata: nil)
    before = tracked_snapshot
    yield if block_given?
    reload
    changed = diff_keys(before, tracked_snapshot)

    recordable_class = self.class.trackable_recordable
    raise "#{self.class} did not declare `tracked_by`" unless recordable_class

    update_attrs = snapshot_attributes.merge(
      update_type:    IncidentEvent.update_type_for(event_type),
      changed_fields: changed
    )
    update_attrs[recordable_class.recorder_attr] = by
    update_attrs[:message] = message if message && recordable_class.column_names.include?("message")

    update = recordable_class.create!(update_attrs)

    event_metadata = (metadata || {}).dup
    event_metadata[:message] = message if message && !recordable_class.column_names.include?("message")

    incident_owner.incident_events.create!(
      event_type: event_type,
      user:       by,
      eventable:  update,
      metadata:   event_metadata
    )
  end

  private

  def incident_owner
    public_send(self.class.trackable_incident_via)
  end

  # The diff snapshot reduces associations to their primary key so that
  # `belongs_to :status` swaps register as a change even though the AR
  # objects themselves are reference-distinct on every reload.
  def tracked_snapshot
    snapshot_attributes.transform_values { |v| v.respond_to?(:id) ? v.id : v }
  end

  def diff_keys(before, after)
    aliases = self.class.trackable_diff_aliases
    before.each_key
      .select { |k| before[k] != after[k] }
      .map { |k| (aliases[k] || k).to_s }
  end
end
