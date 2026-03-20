require "ruby_llm/schema"

class PostmortemGenerationService
  DEFAULT_MODEL = "claude-sonnet-4-6"
  MAX_TRANSCRIPT_MESSAGES = 100

  def initialize(workspace)
    @workspace = workspace
  end

  def generate(incident, generated_by:)
    prompt_data = collect_incident_data(incident)
    ai_result = call_ai(prompt_data)
    postmortem = create_postmortem(incident, ai_result, generated_by: generated_by)
    postmortem.create_initial_update!(edited_by: generated_by)
    postmortem
  end

  def post_message(incident)
    postmortem = incident.postmortem
    return unless postmortem

    adapter = @workspace.adapter
    result = adapter.post_postmortem_message(
      channel_id: incident.channel_id,
      incident: incident,
      postmortem: postmortem
    )
    message_ts = result[:message_ts]
    postmortem.update!(message_ts: message_ts)
    adapter.pin_message(channel_id: incident.channel_id, timestamp: message_ts)
    { message_ts: message_ts }
  end

  private

  def collect_incident_data(incident)
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
      actions: format_actions(incident),
      shoutouts: format_shoutouts(incident)
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
    entries = IncidentTranscriptCache.entries(incident)
    return [] if entries.blank?

    members = @workspace.workspace_memberships.index_by(&:platform_user_id)

    entries.last(MAX_TRANSCRIPT_MESSAGES).map do |entry|
      member = members[entry["user_id"]]
      {
        at: entry["created_at"],
        by: member&.user&.name || entry["user_id"],
        text: entry["text"]
      }
    end
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

  def format_shoutouts(incident)
    incident.shoutouts.map do |shoutout|
      {
        from: shoutout.from_member.user.name,
        to: shoutout.to_member&.user&.name,
        message: shoutout.message
      }
    end
  end

  def call_ai(prompt_data)
    chat = RubyLLM.chat(model: ai_model)
    chat.with_instructions(system_prompt)
    chat.with_schema(PostmortemSchema)
    response = chat.ask(user_prompt(prompt_data))
    response.content
  end

  def create_postmortem(incident, ai_result, generated_by:)
    sections = Postmortem::SECTION_KEYS.filter_map do |key|
      body = ai_result[key.to_s] || ai_result[key.to_sym]
      next if body.blank?

      { "key" => key, "heading" => Postmortem::SECTION_HEADINGS[key], "body" => body }
    end

    Postmortem.create!(
      incident: incident,
      generated_by: generated_by,
      title: ai_result["title"] || ai_result[:title],
      summary: ai_result["summary"] || ai_result[:summary],
      status: Postmortem::STATUS_DRAFT,
      model_id: ai_model,
      content: { "sections" => sections }
    )
  end

  def ai_model
    @ai_model ||= ENV.fetch("POSTMORTEM_AI_MODEL", DEFAULT_MODEL)
  end

  def system_prompt
    <<~PROMPT
      You are an expert incident management analyst writing a postmortem document for an engineering team.

      Your writing should be:
      - Factual and precise — use specific timestamps, metrics, and names from the data provided
      - Blameless — focus on systems and processes, never blame individuals
      - Actionable — contributing factors and action items should lead to concrete improvements
      - Clear — write for a technical audience but keep language accessible

      Use markdown formatting for structure (bold, bullet points, numbered lists).
      For the summary section, use this structure: **Problem**: ... **Impact**: ... **Causes**: ... **Steps to resolve**: ...
    PROMPT
  end

  def user_prompt(data)
    parts = []
    parts << "Generate a postmortem document for the following incident:\n"
    parts << "## Incident Details"
    parts << "- Identifier: #{data[:identifier]}"
    parts << "- Name: #{data[:name]}"
    parts << "- Summary: #{data[:summary]}" if data[:summary].present?
    parts << "- Severity: #{data[:severity]}"
    parts << "- Status: #{data[:status]}"
    parts << "- Declared at: #{data[:declared_at]}"
    parts << "- Detected at: #{data[:detected_at]}" if data[:detected_at]
    parts << "- Resolved at: #{data[:resolved_at]}" if data[:resolved_at]
    parts << "- Duration: #{data[:duration_minutes]} minutes" if data[:duration_minutes]
    parts << "- Declared by: #{data[:declared_by]}"
    parts << "- Incident lead: #{data[:lead]}" if data[:lead]

    if data[:custom_fields].present?
      parts << "\n## Custom Fields"
      data[:custom_fields].each { |k, v| parts << "- #{k}: #{v}" }
    end

    if data[:timeline_events].present?
      parts << "\n## Timeline Events"
      data[:timeline_events].each do |event|
        parts << "- [#{event[:at]}] #{event[:description]} (by #{event[:by] || 'system'})"
      end
    end

    if data[:transcript].present?
      parts << "\n## Channel Transcript (most recent #{data[:transcript].size} messages)"
      data[:transcript].each do |msg|
        parts << "- [#{msg[:at]}] #{msg[:by]}: #{msg[:text]}"
      end
    end

    if data[:actions].present?
      parts << "\n## Actions & Follow-ups"
      data[:actions].each do |action|
        assignee = action[:assignee] ? " (assigned to #{action[:assignee]})" : ""
        parts << "- [#{action[:type]}] #{action[:description]} — #{action[:status]}#{assignee}"
      end
    end

    if data[:shoutouts].present?
      parts << "\n## Shoutouts"
      data[:shoutouts].each do |shoutout|
        to = shoutout[:to] ? " to #{shoutout[:to]}" : ""
        parts << "- #{shoutout[:from]}#{to}: #{shoutout[:message]}"
      end
    end

    parts.join("\n")
  end

  class PostmortemSchema < RubyLLM::Schema
    description "A structured incident postmortem document"

    string :title, description: "A concise postmortem title, e.g. 'INC-031 Postmortem: API Gateway Outage'"
    string :summary, description: "Executive summary using this format: **Problem**: ... **Impact**: ... **Causes**: ... **Steps to resolve**: ..."
    string :introduction, description: "Narrative introduction covering who reported, when, what happened, severity, root cause summary, resolution, and duration"
    string :deeper_dive, description: "Detailed technical narrative with root cause analysis, diagnosis steps, and supporting evidence"
    string :impact, description: "Detailed impact analysis covering affected users, services, and business impact"
    string :resolution, description: "How the issue was fixed, with numbered steps where applicable"
    string :contributing_factors, description: "Bullet list of contributing factors that led to the incident"
    string :what_went_well, description: "Bullet list of what went well during the incident response"
    string :action_items, description: "Bullet list of recommended action items to prevent recurrence"
  end
  private_constant :PostmortemSchema
end
