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
    # if narrows which commits count, for a record that is written far more often than the page changes.
    def shown_on_incident_page(part, **options)
      class_attribute :incident_page_part, instance_writer: false, default: part
      after_commit :signal_incident_page, **options
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

  def signal_incident_page
    Incident::LiveSignal.signal!(incident_page_ids, incident_page_part)
  end

  private

  # A record moved to another incident changes both pages.
  def incident_page_ids
    column = is_a?(Incident) ? "id" : "incident_id"
    [ public_send(column), saved_changes[column]&.first ]
  end
end
