require "ruby_llm/schema"

class IncidentAiService
  DEFAULT_MODEL = "claude-sonnet-4-6"

  def initialize(workspace)
    @workspace = workspace
  end

  def answer_question(incident, question:)
    context = collect_incident_context(incident)
    call_ai(context, question)
  end

  private

  def collect_incident_context(incident)
    {
      identifier: incident.identifier,
      name: incident.name,
      summary: incident.summary,
      severity: incident.incident_severity.name,
      status: incident.incident_status.name,
      declared_at: incident.declared_at&.iso8601,
      detected_at: incident.detected_at&.iso8601,
      resolved_at: incident.resolved_at&.iso8601,
      duration_minutes: incident.time_to_resolve,
      declared_by: incident.declared_by.user.name,
      lead: incident.lead&.user&.name,
      custom_fields: incident.custom_fields,
      timeline_events: format_events(incident),
      transcript: format_transcript(incident),
      actions: format_actions(incident)
    }
  end

  def format_events(incident)
    incident.incident_events.chronological.includes(:user).map do |event|
      {
        type: event.event_type,
        at: event.created_at.iso8601,
        by: event.user&.user&.name,
        description: event.description
      }
    end
  end

  def format_transcript(incident)
    IncidentTranscriptCache.grouped_messages(incident, workspace: @workspace)
  end

  def format_actions(incident)
    incident.incident_actions.active.map do |action|
      {
        type: action.action_type,
        description: action.description,
        status: action.status,
        assignee: action.assignee&.user&.name
      }
    end
  end

  def call_ai(context, question)
    chat = RubyLLM.chat(model: ai_model)
    chat.with_instructions(system_prompt)
    response = chat.ask(user_prompt(context, question))
    response.content
  end

  def system_prompt
    <<~PROMPT
      You are Firefight AI, an incident management assistant embedded in Slack.

      Your role is to help incident responders by answering questions about the current incident based on the data provided. Be:
      - *Concise* — this is Slack, keep responses brief and scannable
      - *Factual* — only reference information from the provided data
      - *Helpful* — highlight the most important details first
      - *Honest* — if the data doesn't contain an answer, say so

      Use Slack mrkdwn formatting: *bold*, _italic_, bullet points, and `code` where appropriate.
      Do not use markdown headers (#) — use *bold text* instead.
    PROMPT
  end

  def user_prompt(context, question)
    parts = []
    parts << "Here is the incident data:\n"
    parts << "## Incident"
    parts << "- Identifier: #{context[:identifier]}"
    parts << "- Name: #{context[:name]}"
    parts << "- Summary: #{context[:summary]}" if context[:summary].present?
    parts << "- Severity: #{context[:severity]}"
    parts << "- Status: #{context[:status]}"
    parts << "- Declared at: #{context[:declared_at]}"
    parts << "- Detected at: #{context[:detected_at]}" if context[:detected_at]
    parts << "- Resolved at: #{context[:resolved_at]}" if context[:resolved_at]
    parts << "- Duration: #{context[:duration_minutes]} minutes" if context[:duration_minutes]
    parts << "- Declared by: #{context[:declared_by]}"
    parts << "- Incident lead: #{context[:lead]}" if context[:lead]

    if context[:timeline_events].present?
      parts << "\n## Timeline Events"
      context[:timeline_events].each do |event|
        parts << "- [#{event[:at]}] #{event[:description]} (by #{event[:by] || 'system'})"
      end
    end

    if context[:transcript].present?
      parts << "\n## Channel Transcript (#{context[:transcript].size} messages)"
      context[:transcript].each do |msg|
        parts << "- [#{msg[:at]}] #{msg[:by]}: #{msg[:text]}"
        (msg[:replies] || []).each do |reply|
          parts << "  - [#{reply[:at]}] #{reply[:by]} (thread reply): #{reply[:text]}"
        end
      end
    end

    if context[:actions].present?
      parts << "\n## Actions & Follow-ups"
      context[:actions].each do |action|
        assignee = action[:assignee] ? " (assigned to #{action[:assignee]})" : ""
        parts << "- [#{action[:type]}] #{action[:description]} — #{action[:status]}#{assignee}"
      end
    end

    parts << "\n## Question"
    parts << question

    parts.join("\n")
  end

  def ai_model
    @ai_model ||= ENV.fetch("INCIDENT_AI_MODEL", DEFAULT_MODEL)
  end
end
