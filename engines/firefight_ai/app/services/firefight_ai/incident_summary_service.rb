module FirefightAi
  class IncidentSummaryService
    FRESHNESS_WINDOW   = 15.minutes
    MAX_INPUT_TOKENS   = 50_000
    SUMMARY_OUTPUT_CAP = 1000

    FEATURE_FULL        = "summary_full"
    FEATURE_INCREMENTAL = "summary_incremental"

    def initialize(workspace)
      @workspace = workspace
    end

    def fetch_or_refresh(incident)
      summary   = incident.incident_summary
      latest_ts = latest_message_ts(incident)

      return nil if latest_ts.nil?
      return safe_full_generate(incident) if summary.nil?
      return summary if summary.summary_up_to_ts == latest_ts
      return summary if summary.generated_at > FRESHNESS_WINDOW.ago

      safe_incremental_refresh(incident, summary) || summary
    end

    private

    # Wrap the two paths that touch the LLM so a failure (rate limit, timeout,
    # transient provider error) degrades to "no summary this time" rather than
    # killing the consumer (catchup, postmortem). Cache hits (paths 1 + 2) are
    # NOT wrapped, they don't touch the LLM and must not be swallowed.
    def safe_full_generate(incident)
      full_generate(incident)
    rescue StandardError => e
      log_failure(incident, e)
      nil
    end

    def safe_incremental_refresh(incident, summary)
      incremental_refresh(incident, summary)
    rescue StandardError => e
      log_failure(incident, e)
      nil
    end

    def log_failure(incident, error)
      Rails.logger.warn({
        event: "incident_summary.failed",
        incident_id: incident.id,
        error_class: error.class.name,
        error: error.message
      }.to_json)
    end

    def latest_message_ts(incident)
      incident.incident_transcript_messages.kept.maximum(:slack_ts)
    end

    def full_generate(incident)
      messages = incident.incident_transcript_messages.kept.order(:posted_at).to_a
      return nil if messages.empty?

      prompt = build_full_prompt(incident, messages)
      response, inference = call_llm(incident, prompt, feature: FEATURE_FULL)
      upsert_summary(incident, response, inference, up_to_ts: messages.last.slack_ts)
    end

    def incremental_refresh(incident, summary)
      delta_top_level, affected_threads, latest_ts = compute_delta(incident, summary.summary_up_to_ts)
      return summary if delta_top_level.empty? && affected_threads.empty?

      prompt = build_incremental_prompt(summary.content, delta_top_level, affected_threads)
      response, inference = call_llm(incident, prompt, feature: FEATURE_INCREMENTAL)
      upsert_summary(incident, response, inference, up_to_ts: latest_ts)
    end

    # Returns [delta_top_level_messages, affected_threads, latest_ts].
    # affected_threads is [{ parent:, replies: }, ...] with the FULL thread
    # (parent + all replies, not just new ones) for any thread that received
    # a new reply since summary_up_to_ts. New top-level messages stay separate.
    def compute_delta(incident, summary_up_to_ts)
      delta = incident.incident_transcript_messages.kept
                .where("slack_ts > ?", summary_up_to_ts)
                .order(:posted_at)
                .to_a

      top_level     = []
      reply_parents = Set.new

      delta.each do |msg|
        parent = msg.slack_thread_ts
        if parent.nil? || parent == msg.slack_ts
          top_level << msg
        else
          reply_parents << parent
        end
      end

      affected = reply_parents.filter_map do |parent_ts|
        parent = incident.incident_transcript_messages.kept.find_by(slack_ts: parent_ts)
        next unless parent

        replies = incident.incident_transcript_messages.kept
                    .where(slack_thread_ts: parent_ts)
                    .where.not(slack_ts: parent_ts)
                    .order(:posted_at)
                    .to_a

        { parent: parent, replies: replies }
      end

      # Use the max slack_ts (lex-ordered), since the next refresh's
      # `where("slack_ts > ?", ...)` filter compares against this column.
      latest_ts = delta.map(&:slack_ts).max || summary_up_to_ts
      [ top_level, affected, latest_ts ]
    end

    def upsert_summary(incident, response, inference, up_to_ts:)
      summary = incident.incident_summary || IncidentSummary.new(incident: incident, workspace: @workspace)
      summary.assign_attributes(
        content:          response.content,
        summary_up_to_ts: up_to_ts,
        generated_at:     Time.current,
        model:            model_id,
        inference:        inference
      )
      summary.save!
      summary
    rescue ActiveRecord::RecordNotUnique
      # Concurrent fetch_or_refresh won the race. Return the persisted winner.
      incident.reload.incident_summary
    end

    def call_llm(incident, prompt_text, feature:)
      Inference.track(
        workspace: @workspace,
        feature:   feature,
        provider:  Inference.provider_for(model_id),
        model:     model_id,
        inferable: incident
      ) do
        chat = RubyLLM.chat(model: model_id)
        chat.with_instructions(system_prompt)
        chat.ask(prompt_text)
      end
    end

    def model_id
      @model_id ||= ENV.fetch("SUMMARY_AI_MODEL", "gpt-4o-mini")
    end

    def system_prompt
      <<~PROMPT
        You are summarizing the chat narrative of an incident. The structured
        timeline (status changes, severity, lead assignments, actions) is
        rendered separately to the reader -- do not retell those events.

        Focus on the conversational narrative around the timeline:
        - Investigation paths and working theories
        - Key decisions made in chat
        - Blockers and open questions
        - Current focus

        Use markdown bullets. Be concise (aim for under #{SUMMARY_OUTPUT_CAP} tokens).
      PROMPT
    end

    def build_full_prompt(incident, messages)
      parts = []
      parts << "Incident: #{incident.identifier} -- #{incident.name}"
      parts << ""
      parts << "Messages (chronological):"
      messages.each { |m| parts << format_message(m) }
      parts.join("\n")
    end

    def build_incremental_prompt(prior_summary, delta_top_level, affected_threads)
      parts = []
      parts << "Prior summary:"
      parts << prior_summary
      parts << ""

      if delta_top_level.any?
        parts << "New top-level messages since the last summary:"
        delta_top_level.each { |m| parts << format_message(m) }
        parts << ""
      end

      if affected_threads.any?
        parts << "Threads with new replies (full thread shown for context):"
        affected_threads.each do |thread|
          parts << format_message(thread[:parent])
          thread[:replies].each { |r| parts << "  #{format_message(r)}" }
        end
      end

      parts.join("\n")
    end

    def format_message(message)
      author = message.workspace_membership&.user&.name || message.slack_user_id
      "- [#{message.posted_at.iso8601}] #{author}: #{message.content}"
    end
  end
end
