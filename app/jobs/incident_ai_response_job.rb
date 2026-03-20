class IncidentAiResponseJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id, channel_id, thread_ts, question)
    incident = Incident.find(incident_id)
    service = IncidentAiService.new(incident.workspace)
    answer = service.answer_question(incident, question: question)
    adapter = incident.workspace.adapter
    blocks = build_blocks(incident, answer)

    if thread_ts
      adapter.post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: answer, blocks: blocks)
    else
      adapter.post_message(channel_id: channel_id, text: answer, blocks: blocks)
    end
  end

  private

  def build_blocks(incident, answer)
    blocks = [
      {
        type: "header",
        text: { type: "plain_text", text: ":fire: #{incident.identifier} — #{incident.name}", emoji: true }
      },
      { type: "divider" }
    ]

    answer.split("\n\n").each do |paragraph|
      next if paragraph.strip.empty?

      blocks << {
        type: "section",
        text: { type: "mrkdwn", text: paragraph.strip[0, 3000] }
      }
    end

    blocks << { type: "divider" }
    blocks << {
      type: "context",
      elements: [ { type: "mrkdwn", text: ":sparkles: _Powered by Firefight AI_" } ]
    }

    blocks
  end
end
