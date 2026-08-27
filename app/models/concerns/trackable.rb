module Trackable
  extend ActiveSupport::Concern

  class_methods do
    def tracked_by(recordable_class, incident_via: nil, diff_aliases: {}, diff_ignores: [])
      @trackable_recordable   = recordable_class
      @trackable_incident_via = incident_via || (name == "Incident" ? :itself : :incident)
      @trackable_diff_aliases = diff_aliases.transform_keys(&:to_sym)
      @trackable_diff_ignores = diff_ignores.map(&:to_sym)
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

    def trackable_diff_ignores
      @trackable_diff_ignores || []
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
      actor:      by,
      eventable:  update,
      metadata:   event_metadata
    )
  end

  private

  def incident_owner
    public_send(self.class.trackable_incident_via)
  end

  # Reduce associations to their primary key so `belongs_to` swaps register as
  # changes, AR objects themselves are reference-distinct on every reload.
  def tracked_snapshot
    snapshot_attributes.transform_values { |v| v.respond_to?(:id) ? v.id : v }
  end

  # diff_ignores keeps platform plumbing (channel ids, message timestamps)
  # out of changed_fields. Those columns are written by jobs and workflow
  # steps outside record_change!, so on a stale instance they would surface
  # as a change made by whoever records the next event.
  def diff_keys(before, after)
    aliases = self.class.trackable_diff_aliases
    ignores = self.class.trackable_diff_ignores
    before.each_key
      .reject { |k| ignores.include?(k) }
      .select { |k| before[k] != after[k] }
      .map { |k| (aliases[k] || k).to_s }
  end
end
