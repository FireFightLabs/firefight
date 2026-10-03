# Learns what an answer marked wrong taught, once its incident has ended, and asks the channel to confirm it.
class IncidentMistakeLearningJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id)
    incident = Incident.find(incident_id)
    saved = IncidentLearningService.new(incident.workspace).learn_from_mistake!(incident)

    Rails.logger.info({ event: "incident_learning.mistake", incident_id: incident_id, lessons: saved.size }.to_json)
  end
end
