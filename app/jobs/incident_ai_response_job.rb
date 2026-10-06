class IncidentAiResponseJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  # Someone asked and is waiting, so they are told why no answer is coming, where the answer would have gone.
  discard_on FirefightAi::OutOfCredit do |job, _error|
    incident_id, channel_id, thread_ts, = job.arguments
    incident = Incident.find_by(id: incident_id)
    job.post(incident, channel_id, thread_ts, AiCredit.cannot(incident.workspace)) if incident
  rescue AdapterError => error
    Rails.logger.warn({ event: "incident_response.out_of_credit_undelivered", incident_id: incident_id, error: error.message }.to_json)
  end

  def perform(incident_id, channel_id, thread_ts, question, scope_thread_ts = nil)
    incident = Incident.find(incident_id)

    unless Entitlements.allows?(incident.workspace, Entitlements::AI)
      Rails.logger.info({ event: "incident_response.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
      return
    end

    answer = FirefightAi::IncidentResponder.new(incident.workspace, output_style: WorkspaceAdapter.for(incident.workspace).ai_output_style)
      .answer_question(incident, question: question, scope_thread_ts: scope_thread_ts)
    post(incident, channel_id, thread_ts, answer)
  end

  def post(incident, channel_id, thread_ts, answer)
    adapter = WorkspaceAdapter.for(incident.workspace)
    if thread_ts
      adapter.post_ai_response_threaded(
        channel_id: channel_id,
        parent_message_id: thread_ts,
        incident: incident,
        answer: answer
      )
    else
      adapter.post_ai_response(channel_id: channel_id, incident: incident, answer: answer)
    end
  end
end
