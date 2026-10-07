module FirefightAi
  class IncidentResponder
    def initialize(workspace, output_style: nil)
      @workspace = workspace
      @output_style = output_style
    end

    def answer_question(incident, question:)
      context = incident.to_full_context(workspace: @workspace)
      summary = IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)
      call_ai(incident, build_incident_prompt(context, summary, question), feature: "incident_catchup")
    end

    private

    def call_ai(incident, prompt_text, feature:)
      response, _ = FirefightAi.generate(ai_model, purpose: AiPurpose::INCIDENT_RESPONSE, inference: {
        workspace: @workspace,
        feature:   feature,
        provider:  ai_model.provider_name,
        model:     ai_model.model,
        inferable: incident,
        prompt_template: "incident_response",
        prompt_version: Prompt.version(system_prompt),
        prompt_text: system_prompt
      }) do |chat|
        chat.with_instructions(system_prompt)
        chat.ask(prompt_text)
      end
      response.content
    end

    DEFAULT_OUTPUT_STYLE = <<~STYLE
      Use markdown for structure: **bold**, _italic_, bullet points, and `code` where appropriate.
      Do not use headers.
    STYLE

    def system_prompt
      <<~PROMPT
        You are Firefight AI, an incident management assistant embedded in the team's chat.

        Your role is to help incident responders by answering questions about the current incident based on the data provided. Be:
        - Concise, this is chat, keep responses brief and scannable
        - Factual, only reference information from the provided data
        - Helpful, highlight the most important details first
        - Honest, if the data doesn't contain an answer, say so

        #{Punctuation::RULE}

        #{@output_style.presence || DEFAULT_OUTPUT_STYLE}

        Do not invite follow-up questions or offer further help. End on the
        last fact, not on conversational closers like "let me know if you have
        questions" or "feel free to reach out".
      PROMPT
    end

    def build_incident_prompt(context, summary, question)
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
        parts.concat(IncidentRecord.timeline(context[:timeline_events]))
        parts.concat(IncidentRecord.status_updates(context[:timeline_events]))
      end

      if summary&.content.present?
        parts << "\n## Narrative Summary"
        parts << summary.content
      end

      if context[:actions].present?
        parts << "\n## Actions & Follow-ups"
        context[:actions].each { |action| parts << IncidentRecord.action_line(action) }
      end

      if context[:runbooks].present?
        parts << "\n## Attached Runbooks"
        context[:runbooks].each do |runbook|
          parts << "### #{runbook[:name]}"
          parts << runbook[:summary] if runbook[:summary].present?
          parts << "Link: #{runbook[:external_url]}" if runbook[:external_url].present?
          runbook[:steps].each_with_index do |step, idx|
            instruction = step[:instruction].present? ? " — #{step[:instruction]}" : ""
            parts << "#{idx + 1}. #{step[:title]}#{instruction}"
          end
        end
      end

      parts << "\n## Question"
      parts << question

      parts.join("\n")
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INCIDENT_RESPONSE, workspace: @workspace)
    end
  end
end
