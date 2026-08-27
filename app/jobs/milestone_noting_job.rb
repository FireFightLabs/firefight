# Reads the transcript of an incident that has just ended and writes its
# milestones onto the timeline. Runs from the close and cancel workflows,
# after the channel has been told the incident is over, so a failure here
# never touches the incident's state or what was posted.
class MilestoneNotingJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id)
    incident = Incident.find(incident_id)
    events = MilestoneNotingService.new(incident.workspace).note!(incident)

    Rails.logger.info({
      event: "milestone_noting.completed",
      incident_id: incident_id,
      notes: events.size
    }.to_json)
  end
end
