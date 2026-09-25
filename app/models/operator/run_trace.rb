module Operator
  # One Halon run on one clock, from every record it left: the job taking it, the facts it started from, each model
  # call and tool call, its theories, its answer or why it stopped, how that reached the thread, and what people said.
  class RunTrace
    include Trace

    DECISION_WORDS = {
      Ability::Invocation::DECISION_ALLOW => "allowed", Ability::Invocation::DECISION_DENY => "denied",
      Ability::Invocation::DECISION_PENDING => "waiting for approval"
    }.freeze

    attr_reader :run

    def initialize(run)
      @run = run
    end

    def groups
      @groups ||= [ Trace.build_group("run", "Run", [
        job_span, facts_span, *model_spans, *tool_spans, *theory_spans, critique_span, answer_span, stop_span,
        *post_spans, *platform_spans, *verdict_spans
      ].compact) ]
    end

    def spans = groups.flat_map(&:spans)

    def body_for(key) = spans.find { |span| span.key == key }&.read_body

    # The wording the run started with, which the health page compares.
    def prompt_version = inferences.find { |inference| inference.feature == FirefightAi::Investigator::FEATURE }&.prompt_version

    def model = inferences.first&.model

    private

    def job_span
      return nil unless run.started_at

      Trace.span(
        key: "job", kind: KIND_JOB, title: "Job claimed", started_at: run.started_at, tone: run.attempts > 1 ? IncidentProcess::TONE_WARN : IncidentProcess::TONE_OK,
        detail: "InvestigationJob · attempt #{run.attempts} · lease #{Investigation::LEASE.inspect}",
        facts: [
          [ "Attempts", "#{run.attempts} of #{Investigation::MAX_ATTEMPTS}" ], [ "Held by", run.lease_holder ],
          [ "Lease until", run.lease_until&.utc&.iso8601 ], [ "Asked from", run.trigger_source ],
          [ "Asked by", run.triggered_by.try(:principal_label) ], [ "Turn limit", run.max_turns ],
          [ "Spend limit", Money.dollars(run.max_spend_cents * FirefightAi::AgentLoop::MICROS_PER_CENT) ],
          [ "Model chosen for this run", run.model_override ], [ "Replay of", run.replay_of_id ]
        ]
      )
    end

    def facts_span
      pack = run.seed_pack
      return nil if pack.blank?

      # Whatever the seeder gathered, counted by section, so a new section shows without a change here.
      counted = pack.filter_map do |name, value|
        "#{value.size} #{name.humanize(capitalize: false)}" if value.is_a?(Array) && value.any?
      end
      Trace.span(
        key: "facts", kind: KIND_FACTS, title: "Facts gathered",
        started_at: parse_time(pack[Investigation::Seeding::KEY_GATHERED_AT]) || run.started_at || run.created_at,
        detail: [ *counted, ("the brief" if run.brief.present?) ].compact.join(" · "),
        facts: [ [ "Question", run.question ], [ "Sections", pack.keys.join(", ") ] ],
        body: -> { pack }
      )
    end

    def model_spans
      inferences.each_with_index.map do |inference, index|
        ended = inference.created_at
        started = ended - (inference.latency_ms / 1000.0)
        check = inference.feature == FirefightAi::CitationCheck::FEATURE
        failed = inference.status == Inference::STATUS_ERROR
        message = check ? nil : assistant_message_between(started, ended)
        Trace.span(
          key: "model-#{inference.id}", kind: check ? KIND_CHECK : KIND_MODEL, title: check ? "Citation re-read" : "Model call #{index + 1}",
          started_at: started, ended_at: ended, tone: failed ? IncidentProcess::TONE_BAD : IncidentProcess::TONE_INFO,
          detail: failed ? inference.error_class : model_detail(inference),
          facts: [
            [ "Model", "#{inference.provider} #{inference.model}" ], [ "Input tokens", inference.input_tokens ],
            [ "Read from cache", inference.cache_read_tokens ], [ "Written to cache", inference.cache_write_tokens ],
            [ "Output tokens", inference.output_tokens ], [ "Cost", Money.dollars(inference.cost_micros) ],
            [ "Took", "#{inference.latency_ms} ms" ], [ "Stopped because", inference.stop_reason ],
            [ "Prompt", [ inference.prompt_template, inference.prompt_version ].compact.join(" ") ],
            [ "Provider request", inference.provider_request_id ], [ "Error", inference.error_class ]
          ],
          body: message && -> { message_text(message) }
        )
      end
    end

    def tool_spans
      run.steps.includes(:invocation).map do |step|
        invocation = step.invocation
        denied = invocation&.decision == Ability::Invocation::DECISION_DENY
        failed = step.status == Investigation::Step::STATUS_FAILED
        Trace.span(
          key: "tool-#{step.id}", kind: KIND_TOOL, title: step.tool_name || step.action_key.to_s,
          started_at: step.started_at || step.created_at, ended_at: step.completed_at,
          tone: failed || denied ? IncidentProcess::TONE_BAD : IncidentProcess::TONE_OK,
          detail: [ DECISION_WORDS.fetch(invocation&.decision, "replayed from its record"), Trace.seconds(step.started_at, step.completed_at), Trace.size(step.raw_result), step.error_summary ].compact.join(" · "),
          facts: [
            [ "Step", step.position ], [ "Action", step.action_key ], [ "Decision", invocation && DECISION_WORDS.fetch(invocation.decision, invocation.decision) ],
            [ "As", invocation&.principal_label ], [ "Scope", invocation&.scope.presence&.to_json ],
            [ "Took", invocation&.duration_ms && "#{invocation.duration_ms} ms" ], [ "Returned", Trace.size(step.raw_result) ],
            [ "Kept for the model", Trace.size(step.compacted_result) ], [ "Asked with", step.params.presence&.to_json ],
            [ "Why", step.reasoning ], [ "Error", step.error_summary || invocation&.error_summary ], [ "Ledger", invocation&.id ]
          ],
          body: -> { step.raw_result.presence || step.compacted_result.to_s }
        )
      end
    end

    def theory_spans
      run.hypotheses.map do |theory|
        Trace.span(
          key: "theory-#{theory.id}", kind: KIND_THEORY, title: "Theory recorded", started_at: theory.created_at,
          tone: theory.status == Investigation::Hypothesis::STATUS_REFUTED ? IncidentProcess::TONE_IDLE : IncidentProcess::TONE_INFO,
          detail: "#{theory.assertion} · #{theory.status}",
          facts: [ [ "Status", theory.status ], [ "Confidence", theory.confidence&.to_s ], [ "Last changed", theory.updated_at.utc.iso8601 ] ]
        )
      end
    end

    def critique_span
      return nil unless run.critique_asked_at

      Trace.span(key: "critique", kind: KIND_CHECK, title: "Critique", started_at: run.critique_asked_at, tone: IncidentProcess::TONE_INFO,
                 detail: "Asked to argue with its first answer before concluding")
    end

    def answer_span
      finding = run.finding
      return nil unless finding

      Trace.span(
        key: "answer", kind: KIND_ANSWER, title: "Answer recorded", started_at: finding.created_at, detail: finding.summary,
        facts: [
          [ "Cause", finding.winning_hypothesis&.assertion ], [ "Evidence", finding.evidence_items.size ],
          [ "Suggests an incident", ("yes" if finding.suggests_incident) ], [ "Team says", finding.outcome ]
        ],
        body: -> { answer_text(finding) }
      )
    end

    def stop_span
      return nil if run.finding || run.completed_at.nil?

      ending = HalonRuns.ending(run.status, run.error_summary)
      Trace.span(
        key: "stop", kind: KIND_STOP, title: ending == HalonRuns::ENDING_FAILED ? "Failed" : "Stopped", started_at: run.completed_at,
        tone: ending == HalonRuns::ENDING_FAILED ? IncidentProcess::TONE_BAD : IncidentProcess::TONE_WARN,
        detail: run.stopped_because || run.error_summary,
        facts: [ [ "Status", run.status ], [ "Recorded cause", run.error_summary ] ]
      )
    end

    def post_spans
      return [] if run.thread_id.blank?

      started = Trace.span(key: "thread", kind: KIND_POST, title: "Thread opened", started_at: run.started_at || run.created_at,
                           detail: "Told the channel it is investigating", facts: [ [ "Channel", run.channel_id ], [ "Thread", run.thread_id ] ])
      answered = if run.answer_posted_at
        Trace.span(key: "posted", kind: KIND_POST, title: "Posted to the thread", started_at: run.answer_posted_at,
                   detail: run.finding ? "The answer" : "Why it stopped")
      elsif run.over?
        Trace.span(key: "not-posted", kind: KIND_POST, title: "Not posted", started_at: run.completed_at, tone: IncidentProcess::TONE_BAD,
                   detail: "Finished, but the last post did not reach the thread")
      end
      [ started, answered ].compact
    end

    def platform_spans
      return [] if run.channel_id.blank?

      window = run.created_at..((run.completed_at || Time.current) + 5.minutes)
      PlatformCallFailure.where(workspace_id: run.workspace_id, channel_id: run.channel_id, created_at: window).map do |failure|
        Trace.span(key: "platform-#{failure.id}", kind: KIND_PLATFORM, title: "#{failure.platform.titleize} #{failure.operation} failed",
                   started_at: failure.created_at, tone: IncidentProcess::TONE_BAD, detail: failure.error_class,
                   facts: [ [ "Error", failure.error_class ], [ "Message", failure.message ] ])
      end
    end

    def verdict_spans
      return [] unless run.finding

      run.finding.verdicts.includes(:member).map do |verdict|
        Trace.span(key: "verdict-#{verdict.id}", kind: KIND_VERDICT, title: "#{verdict.member.display_name} said #{verdict.outcome}",
                   started_at: verdict.created_at, tone: verdict.outcome == Investigation::Finding::OUTCOME_WRONG ? IncidentProcess::TONE_WARN : IncidentProcess::TONE_OK)
      end
    end

    def inferences
      @inferences ||= Inference.where(inferable: run).order(:created_at).to_a
    end

    def assistant_messages
      @assistant_messages ||= run.chat ? run.chat.messages.where(role: Chat::Message::ROLE_ASSISTANT).to_a : []
    end

    # The loop saves each reply as its call returns, so a call's reply is the first saved inside it or just after.
    def assistant_message_between(started, ended)
      assistant_messages.find { |message| message.created_at >= started && message.created_at <= ended + 2.seconds }
    end

    def model_detail(inference)
      cached = inference.cache_read_tokens.positive? ? ", #{Trace.tokens(inference.cache_read_tokens)} cached" : ""
      "#{Trace.tokens(inference.input_tokens + inference.cache_read_tokens)} in#{cached} · #{Trace.tokens(inference.output_tokens)} out · #{Money.dollars(inference.cost_micros)}"
    end

    def message_text(message)
      calls = RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: message.id).map do |call|
        "#{call.name} #{call.arguments.to_json}"
      end
      [
        ("Thinking\n#{message.thinking_text}" if message.thinking_text.present?),
        ("Said\n#{message.content}" if message.content.present?),
        ("Asked for\n#{calls.join("\n")}" if calls.any?)
      ].compact.join("\n\n")
    end

    def answer_text(finding)
      evidence = finding.evidence_items.map { |item| "- #{item.claim}" }
      [
        finding.summary, ("Cause\n#{finding.winning_hypothesis.assertion}" if finding.winning_hypothesis),
        ("Evidence\n#{evidence.join("\n")}" if evidence.any?), ("Could not check\n#{finding.gaps}" if finding.gaps.present?)
      ].compact.join("\n\n")
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
