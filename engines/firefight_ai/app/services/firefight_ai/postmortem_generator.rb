module FirefightAi
  class PostmortemGenerator
    def initialize(workspace)
      @workspace = workspace
    end

    def generate(incident, generated_by:)
      prompt_data = incident.to_full_context(workspace: @workspace)
      summary = IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)
      ai_result = call_ai(prompt_data, summary)
      postmortem = create_postmortem(incident, ai_result, generated_by: generated_by)
      postmortem.record_change!(IncidentEvent::POSTMORTEM_GENERATED, by: generated_by)
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
      message_ts = result[:message_id]
      postmortem.update!(message_ts: message_ts)
      adapter.pin_message(channel_id: incident.channel_id, message_id: message_ts)
      { message_ts: message_ts }
    end

    private

    def call_ai(prompt_data, summary)
      chat = RubyLLM.chat(model: ai_model)
      chat.with_instructions(system_prompt)
      chat.with_schema(Schemas::Postmortem)
      response = chat.ask(user_prompt(prompt_data, summary))
      response.content
    end

    def create_postmortem(incident, ai_result, generated_by:)
      html = Postmortem::SECTION_KEYS.filter_map do |key|
        body = ai_result[key.to_s] || ai_result[key.to_sym]
        next if body.blank?

        heading = Postmortem::SECTION_HEADINGS[key]
        rendered = Commonmarker.to_html(body, options: { parse: { smart: true }, render: { unsafe: true } })
        "<h2>#{heading}</h2>\n#{rendered}"
      end.join("\n")

      Postmortem.create!(
        incident: incident,
        generated_by: generated_by,
        title: ai_result["title"] || ai_result[:title],
        summary: ai_result["summary"] || ai_result[:summary],
        status: Postmortem::STATUS_DRAFT,
        model_id: ai_model,
        content: { "html" => html }
      )
    end

    def ai_model
      @ai_model ||= ENV.fetch("POSTMORTEM_AI_MODEL", "gpt-4o")
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

    MAX_TIMELINE_EVENTS = 200

    def user_prompt(data, summary)
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
        events, elided = capped(data[:timeline_events], MAX_TIMELINE_EVENTS)
        suffix = elided.positive? ? " (#{elided} earlier events elided for length)" : ""
        parts << "\n## Timeline Events#{suffix}"
        events.each do |event|
          parts << "- [#{event[:at]}] #{event[:description]} (by #{event[:by] || 'system'})"
        end
      end

      if summary&.content.present?
        parts << "\n## Narrative Summary"
        parts << summary.content
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

    def capped(collection, limit)
      return [ collection, 0 ] if collection.size <= limit

      [ collection.last(limit), collection.size - limit ]
    end
  end
end
