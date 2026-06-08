module FirefightAi
  class IncidentResponder
    def initialize(workspace)
      @workspace = workspace
    end

    def answer_question(incident, question:)
      context = incident.to_full_context(workspace: @workspace)
      summary = IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)
      call_ai(context, summary, question)
    end

    private

    def call_ai(context, summary, question)
      chat = RubyLLM.chat(model: ai_model)
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt(context, summary, question))
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

    def user_prompt(context, summary, question)
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

      if summary&.content.present?
        parts << "\n## Narrative Summary"
        parts << summary.content
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
      @ai_model ||= ENV.fetch("INCIDENT_AI_MODEL", FirefightAi.configuration.default_model)
    end
  end
end
