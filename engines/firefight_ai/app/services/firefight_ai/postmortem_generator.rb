module FirefightAi
  class PostmortemGenerator
    def initialize(workspace)
      @workspace = workspace
    end

    # Markdown per section, keyed as in Schemas::Postmortem. prompt is the input the model was given, for an audit.
    Draft = Struct.new(:title, :summary, :sections, :model, :prompt, keyword_init: true)

    def generate(incident)
      prompt_data = incident.to_full_context(workspace: @workspace)
      summary = IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)
      prompt = user_prompt(prompt_data, summary, channel_messages: incident.incident_transcript_messages.kept.exists?)
      ai_result = call_ai(incident, prompt)

      sections = Schemas::Postmortem::SECTION_KEYS.to_h do |key|
        [ key, ai_result[key] || ai_result[key.to_sym] ]
      end
      Draft.new(
        title: ai_result["title"] || ai_result[:title],
        summary: ai_result["summary"] || ai_result[:summary],
        sections: sections.compact,
        model: ai_model.model,
        prompt: prompt
      )
    end

    private

    def call_ai(incident, prompt)
      response, _ = FirefightAi.generate(ai_model, purpose: AiPurpose::POSTMORTEM, inference: {
        workspace: @workspace,
        feature:   "postmortem_generate",
        provider:  ai_model.provider_name,
        model:     ai_model.model,
        inferable: incident,
        prompt_template: "postmortem_generate",
        prompt_version: Prompt.version(system_prompt),
        prompt_text: system_prompt
      }) do |chat|
        chat.with_instructions(system_prompt)
        chat.with_schema(Schemas::Postmortem)
        chat.ask(prompt)
      end
      # Structured output arrives as JSON text, parsed is the hash.
      response.parsed
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace)
    end

    def system_prompt
      <<~PROMPT
        You are an expert incident management analyst writing a postmortem document for an engineering team.

        Your writing should be:
        - Factual and precise. Use specific timestamps, metrics, and names from the data provided
        - Blameless. Focus on systems and processes, never blame individuals
        - Actionable. Contributing factors and action items should lead to concrete improvements
        - Clear. Write for a technical audience but keep language accessible

        Write only what the incident record below supports. The record is the incident details, the timeline events, the status updates responders posted, the narrative summary of the channel, the actions and the shoutouts. Never infer a cause, an impact, a fix, what went well, or an action item from the title, the severity, or the duration alone. When the record has nothing for a section, return null for that section. A short incident with little in its record gets a short document, and that is the right answer.

        Use markdown formatting for structure (bold, bullet points, numbered lists).
        For the summary section, use this structure: **Problem**: ... **Impact**: ... **Causes**: ... **Steps to resolve**: ...
        The follow-ups already recorded on the incident are listed under Action items by Firefight itself, so never repeat one in action_items.
      PROMPT
    end

    MAX_TIMELINE_EVENTS = 200

    # Only what is known about the channel, so the model never reads an empty transcript as a silent incident.
    def channel_note(channel_messages)
      if channel_messages
        "The messages people wrote in the incident channel could not be summarized, so there is no narrative summary. " \
          "Do not read its absence as nothing having been said."
      else
        "Firefight holds no messages that people wrote in the incident channel, so there is no narrative summary of the " \
          "conversation. Firefight's own posts, such as status updates, are not part of that record."
      end
    end

    def user_prompt(data, summary, channel_messages: false)
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
        parts.concat(IncidentRecord.timeline(events))
        parts.concat(IncidentRecord.status_updates(data[:timeline_events]))
      end

      if summary&.content.present?
        parts << "\n## Narrative Summary"
        parts << summary.content
      else
        parts << "\n## Channel Conversation"
        parts << channel_note(channel_messages)
      end

      if data[:actions].present?
        parts << "\n## Actions & Follow-ups"
        data[:actions].each { |action| parts << IncidentRecord.action_line(action) }
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
