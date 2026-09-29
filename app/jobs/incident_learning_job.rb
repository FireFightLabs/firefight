# Runs after the channel has been told the incident is over, or after its postmortem is completed, so a failure here
# never touches the incident or what was posted.
class IncidentLearningJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id, from_postmortem = false)
    incident = Incident.find(incident_id)
    postmortem = incident.postmortem if from_postmortem
    return if from_postmortem && postmortem.nil?

    saved = IncidentLearningService.new(incident.workspace).learn!(incident, postmortem: postmortem)

    Rails.logger.info({ event: "incident_learning.completed", incident_id: incident_id, from_postmortem: from_postmortem, lessons: saved.size }.to_json)
  end
end
