# Answers /ff catchup with one reply in the incident's channel.
class IncidentAiResponseJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  # Someone asked and is waiting, so they are told why no answer is coming, where the answer would have gone.
  discard_on FirefightAi::OutOfCredit do |job, _error|
    incident_id, channel_id, = job.arguments
    incident = Incident.find_by(id: incident_id)
    job.post(incident, channel_id, AiCredit.cannot(incident.workspace)) if incident
  rescue AdapterError => error
    Rails.logger.warn({ event: "incident_response.out_of_credit_undelivered", incident_id: incident_id, error: error.message }.to_json)
  end

  # A job queued before replies left threads carries (thread, question, scope) after the channel, and is answered in
  # the channel like any other.
  def perform(incident_id, channel_id, *asked)
    question = asked.one? ? asked.first : asked.second
    incident = Incident.find(incident_id)

    unless Entitlements.allows?(incident.workspace, Entitlements::AI)
      Rails.logger.info({ event: "incident_response.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
      return
    end

    answer = FirefightAi::IncidentResponder.new(incident.workspace, output_style: WorkspaceAdapter.for(incident.workspace).ai_output_style)
      .answer_question(incident, question: question)
    post(incident, channel_id, answer)
  end

  def post(incident, channel_id, answer)
    WorkspaceAdapter.for(incident.workspace).post_ai_response(channel_id: channel_id, incident: incident, answer: answer)
  end
end
