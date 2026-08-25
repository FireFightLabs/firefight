module FirefightAi
  # Reads an incident's channel transcript once and returns the milestones of
  # the investigation: what was theorised, found, decided, and fixed. Returns
  # data. Writing them onto the timeline is the app's job.
  class MilestoneExtractor
    FEATURE = "milestones"

    # Below this the model is guessing, and a wrong note costs more trust than
    # a missing one buys.
    MIN_CONFIDENCE = 0.7

    # Roughly four characters to a token. The transcript is trimmed from the
    # oldest end because the summary already covers what gets cut, and the
    # decisive part of an incident is at the end.
    MAX_INPUT_TOKENS = 60_000
    CHARS_PER_TOKEN = 4

    MAX_TIMELINE_SENTENCES = 200

    Milestone = Data.define(:kind, :statement, :message_id, :confidence)

    # The ledger row for the pass that produced the last result, so the caller
    # can point each note it writes back at the inference it came from.
    attr_reader :last_inference

    def initialize(workspace)
      @workspace = workspace
    end

    # messages: the transcript rows to read, oldest first.
    # summary:  the incident's IncidentSummary, or nil.
    # timeline: the sentences already on the timeline, so nothing is re-noted.
    def extract(incident, messages:, summary: nil, timeline: [])
      return [] if messages.empty?

      kept = within_budget(messages)
      response = call_ai(incident, prompt(incident, kept, summary, timeline))

      known_ids = kept.map(&:message_id).to_set
      milestones(response).select { |milestone| known_ids.include?(milestone.message_id) }
    end

    private

    def milestones(response)
      content = response.content
      rows = content.is_a?(Hash) ? content.with_indifferent_access[Schemas::Milestones::ROOT_KEY] : nil

      Array(rows).filter_map do |row|
        row = row.with_indifferent_access
        confidence = row[:confidence].to_f
        next if confidence < MIN_CONFIDENCE
        next unless ::IncidentEvent::MILESTONE_KINDS.include?(row[:kind])
        next if row[:statement].blank? || row[:message_id].blank?

        Milestone.new(
          kind: row[:kind],
          statement: row[:statement].to_s.strip,
          message_id: row[:message_id].to_s,
          confidence: confidence
        )
      end
    end

    # Newest messages win the budget. Dropping from the front keeps the
    # transcript contiguous, so the model never reads a stitched-together
    # conversation.
    def within_budget(messages)
      budget = MAX_INPUT_TOKENS * CHARS_PER_TOKEN
      kept = []
      size = 0

      messages.reverse_each do |message|
        size += format_message(message).length
        break if size > budget && kept.any?

        kept.unshift(message)
      end
      kept
    end

    def call_ai(incident, prompt_text)
      response, @last_inference = FirefightAi.translating_errors do
        Inference.track(
          workspace: @workspace,
          feature:   FEATURE,
          provider:  model_choice.provider_name,
          model:     model_choice.model,
          inferable: incident
        ) do
          chat = FirefightAi.chat(model_choice)
          chat.with_instructions(system_prompt)
          chat.with_schema(Schemas::Milestones)
          chat.ask(prompt_text)
        end
      end
      response
    end

    def model_choice
      @model_choice ||= FirefightAi.model_for(AiPurpose::MILESTONES, workspace: @workspace)
    end

    def system_prompt
      <<~PROMPT
        You are reading the chat transcript of an incident that is now over, and
        writing down the milestones of how it was debugged. A milestone is a
        moment a reader six months from now would want, and nothing else.

        Pick one kind for each:

        - hypothesis: someone puts forward a theory about the cause
        - finding: someone confirms or rules something out with evidence
        - root_cause: the cause is identified
        - mitigation: something is done that reduces or stops the impact
        - decision: the team commits to a course of action
        - blocker: the response is stuck waiting on something
        - impact: what is broken, for whom, is established
        - recovery: the system is observed back to normal

        Never note any of these:

        - greetings, acknowledgements, thanks, jokes, and small talk
        - questions nobody answered
        - anything already on the timeline you are given, such as status
          changes, severity changes, escalations, role assignments, action
          items, and runbook attachments
        - restatements of a milestone you have already written down

        Rules:

        - Each milestone comes from exactly one message. Copy that message's
          message_id verbatim.
        - Write the statement as one plain sentence in the past tense, naming
          the person it belongs to, e.g. "Diego suspected the 14:02 deploy" or
          "Uros rolled back the 14:02 deploy". Past tense holds even for a
          theory that was live at the time, so the note reads alongside the
          rest of the timeline. Where a milestone belongs to nobody in
          particular, state the fact: "Error rate returned to baseline".
        - No trailing period, no markdown, no user mentions.
        - Set confidence honestly. A transcript with nothing worth noting
          should return an empty list, and that is a good answer.
      PROMPT
    end

    def prompt(incident, messages, summary, timeline)
      parts = []
      parts << "Incident: #{incident.identifier} - #{incident.name}"
      parts << ""

      if summary&.content.present?
        parts << "## Narrative summary so far"
        parts << summary.content
        parts << ""
      end

      if timeline.any?
        parts << "## Already recorded on the timeline (never note these again)"
        timeline.last(MAX_TIMELINE_SENTENCES).each { |sentence| parts << "- #{sentence}" }
        parts << ""
      end

      parts << "## Transcript (chronological)"
      messages.each { |message| parts << format_message(message) }
      parts.join("\n")
    end

    def format_message(message)
      author = message.workspace_membership&.user&.name || message.platform_user_id
      "- [#{message.message_id}] [#{message.posted_at.iso8601}] #{author}: #{message.content}"
    end
  end
end
