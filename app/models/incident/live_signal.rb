# Says which part of an incident's page changed, once the change commits, so an open page reads that part again.
# Every record the page shows includes it and names its part, so a change from Slack, the API, MCP, Halon, a workflow,
# a job or the page itself is said the same way. A write that skips callbacks (a guarded update_all) calls
# signal_incident_page itself once it wins. The model only says it happened, as an EVENT notification, and
# Incident::LiveDelivery is what tells the pages.
module Incident::LiveSignal
  extend ActiveSupport::Concern

  PART_INCIDENT = "incident"
  PART_TIMELINE = "timeline"
  PART_ACTIONS = "actions"
  PART_POSTMORTEM = "postmortem"
  PART_INVESTIGATION = "investigation"
  PARTS = {
    "INCIDENT" => PART_INCIDENT, "TIMELINE" => PART_TIMELINE, "ACTIONS" => PART_ACTIONS,
    "POSTMORTEM" => PART_POSTMORTEM, "INVESTIGATION" => PART_INVESTIGATION
  }.freeze
  EVENT = "changed.incident_page"

  class_methods do
    # if narrows which saves count, for a record that is written far more often than the page changes. It is asked after
    # each save, since one transaction can save a record several times and only the last save's changes are left by commit.
    def shown_on_incident_page(part, **options)
      class_attribute :incident_page_part, instance_writer: false, default: part
      class_attribute :incident_page_condition, instance_writer: false, default: options[:if]
      after_save :note_incident_page_change
      after_rollback :forget_incident_page_change
      after_commit :signal_incident_page_on_commit
    end
  end

  # Waits for the outermost transaction, so a change that rolls back is never announced.
  def self.signal!(incident_ids, part)
    ids = Array(incident_ids).compact.uniq
    return if ids.empty?

    ActiveRecord.after_all_transactions_commit do
      ids.each { |id| ActiveSupport::Notifications.instrument(EVENT, incident_id: id, part: part) }
    end
  end

  # For a write that skips callbacks, once it wins.
  def signal_incident_page
    Incident::LiveSignal.signal!(incident_page_id, incident_page_part)
  end

  private

  def incident_page_id = is_a?(Incident) ? id : incident_id

  # The incident this save took the record away from, if it moved. A record that holds its incident another way says so.
  def incident_page_id_before_save
    saved_changes["incident_id"]&.first unless is_a?(Incident)
  end

  def note_incident_page_change
    left = incident_page_id_before_save
    (@incident_pages_left ||= []) << left if left
    @incident_page_due ||= incident_page_condition.nil? || instance_exec(&incident_page_condition)
  end

  def forget_incident_page_change
    @incident_pages_left = nil
    @incident_page_due = nil
  end

  # A record moved to another incident changes both pages, however many times it was saved on the way.
  def signal_incident_page_on_commit
    left = @incident_pages_left || []
    due = @incident_page_due || destroyed? || left.any?
    forget_incident_page_change
    Incident::LiveSignal.signal!([ incident_page_id, *left ], incident_page_part) if due
  end
end
