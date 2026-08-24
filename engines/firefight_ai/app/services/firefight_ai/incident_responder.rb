module FirefightAi
  class IncidentResponder
    def initialize(workspace)
      @workspace = workspace
    end

    def answer_question(incident, question:, scope_thread_ts: nil)
      if scope_thread_ts
        thread_messages = thread_messages_for(incident, scope_thread_ts)
        return "I don't see any messages in this thread yet to summarize." if thread_messages.empty?

        call_ai(incident, build_thread_prompt(incident, thread_messages, question), feature: "thread_catchup")
      else
        context = incident.to_full_context(workspace: @workspace)
        summary = IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)
        call_ai(incident, build_incident_prompt(context, summary, question), feature: "incident_catchup")
      end
    end

    private

    def call_ai(incident, prompt_text, feature:)
      response, _ = Inference.track(
        workspace: @workspace,
        feature:   feature,
        provider:  Inference.provider_for(ai_model),
        model:     ai_model,
        inferable: incident
      ) do
        chat = RubyLLM.chat(model: ai_model)
        chat.with_instructions(system_prompt)
        chat.ask(prompt_text)
      end
      response.content
    end

    def thread_messages_for(incident, parent_ts)
      incident.incident_transcript_messages.kept
        .where("slack_ts = ? OR slack_thread_ts = ?", parent_ts, parent_ts)
        .order(:posted_at)
        .to_a
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

        Do not invite follow-up questions or offer further help. End on the
        last fact, not on conversational closers like "let me know if you have
        questions" or "feel free to reach out".
      PROMPT
    end

    def build_thread_prompt(incident, messages, question)
      parts = []
      parts << "You are answering about a single thread in incident #{incident.identifier} — #{incident.name}."
      parts << "Only the messages in this thread are provided. Do not invent context from outside the thread."
      parts << ""
      parts << "## Thread Messages"
      messages.each do |m|
        author = m.workspace_membership&.user&.name || m.slack_user_id
        parts << "- [#{m.posted_at.iso8601}] #{author}: #{m.content}"
      end
      parts << ""
      parts << "## Question"
      parts << question
      parts.join("\n")
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
      @ai_model ||= FirefightAi.model_for("INCIDENT_AI_MODEL", "gpt-4o-mini")
    end
  end
end
