module FirefightAi
  class PostmortemSectionRewriter
    FEATURE = "postmortem_rewrite"

    def initialize(workspace)
      @workspace = workspace
    end

    def rewrite(incident, selected_html:, instruction:)
      context = incident.to_full_context(workspace: @workspace)
      summary = IncidentSummaryService.new(@workspace).fetch_or_refresh(incident)

      response, _ = Inference.track(
        workspace: @workspace,
        feature:   FEATURE,
        provider:  Inference.provider_for(model_id),
        model:     model_id,
        inferable: incident
      ) do
        chat = RubyLLM.chat(model: model_id)
        chat.with_instructions(system_prompt)
        chat.ask(build_prompt(context, summary, selected_html, instruction))
      end

      sanitize_html(response.content)
    end

    private

    def model_id
      @model_id ||= FirefightAi.model_for("POSTMORTEM_AI_MODEL", "gpt-4o")
    end

    def system_prompt
      <<~PROMPT
        You are editing one section of an incident postmortem. Rewrite only the
        SELECTED HTML according to the user's instruction. Preserve formatting
        (HTML tags) and the surrounding writing style.

        Output ONLY the rewritten HTML for the selection. No commentary, no
        markdown fences, no preamble. The output replaces the selection inline,
        so it must be valid HTML that fits in place where the selection was.
      PROMPT
    end

    def build_prompt(context, summary, selected_html, instruction)
      parts = []
      parts << "## Incident Context"
      parts << "- Identifier: #{context[:identifier]}"
      parts << "- Name: #{context[:name]}"
      parts << "- Summary: #{context[:summary]}" if context[:summary].present?
      parts << "- Severity: #{context[:severity]}"
      parts << "- Status: #{context[:status]}"
      parts << "- Declared at: #{context[:declared_at]}"
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

      parts << "\n## Selected HTML"
      parts << selected_html

      parts << "\n## User Instruction"
      parts << instruction

      parts.join("\n")
    end

    def sanitize_html(html)
      Rails::Html::SafeListSanitizer.new.sanitize(
        html.to_s,
        tags: ::Postmortem::Snapshots::ALLOWED_TAGS,
        attributes: ::Postmortem::Snapshots::ALLOWED_ATTRIBUTES
      )
    end
  end
end
