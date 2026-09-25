module Operator
  # A chat with Halon, one turn at a time, each on its own clock: what the person asked, every model call and tool call
  # that followed, the reply, and any run the turn started. Drawn from the chat's saved messages and the model's usage
  # rows, since a chat's ledger rows name the incident it is about rather than the chat.
  class ChatTrace
    include Trace

    # The latest turns, so a long chat still opens quickly.
    TURN_LIMIT = 20
    USAGE_FAILED = RubyLLM::Accounting::Usage::Entry::STATUSES.find { |status| status == :failed }.to_s

    attr_reader :conversation

    # Chats active in the window, the latest first, each with a saved chat to draw.
    def self.recent(filter)
      filter.scope(Conversation.joins(:chat).where(updated_at: filter.range)).includes(:workspace, :subject).order(updated_at: :desc, id: :desc)
    end

    def initialize(conversation)
      @conversation = conversation
    end

    def groups
      @groups ||= turns.last(TURN_LIMIT).each_with_index.map do |messages, index|
        number = turn_count - [ turn_count, TURN_LIMIT ].min + index + 1
        Trace.build_group("turn-#{messages.first.id}", "Turn #{number}", turn_spans(messages))
      end
    end

    def turn_count = turns.size

    def spans = groups.flat_map(&:spans)

    def body_for(key) = spans.find { |span| span.key == key }&.read_body

    private

    def messages
      @messages ||= conversation.chat ? conversation.chat.messages.to_a : []
    end

    # A turn starts at each thing the person said. The loop's own nudges are part of the turn they fall in.
    def turns
      @turns ||= messages.reject { |message| message.role == Chat::Message::ROLE_SYSTEM }
                         .slice_before { |message| person_said?(message) }.select { |turn| person_said?(turn.first) }
    end

    def person_said?(message) = message.role == Chat::Message::ROLE_USER && !message.nudge

    def turn_spans(turn)
      ask = turn.first
      finished = turn.last.created_at
      [
        Trace.span(key: "ask-#{ask.id}", kind: KIND_ASK, title: "Asked", started_at: ask.created_at, tone: IncidentProcess::TONE_INFO,
                   detail: ask.content.to_s.squish.truncate(140), body: -> { ask.content.to_s }),
        *model_spans(turn), *tool_spans(turn), reply_span(turn), *run_spans(ask.created_at, finished)
      ].compact
    end

    def model_spans(turn)
      ids = turn.map(&:id)
      usages.select { |usage| ids.include?(usage.message_id) }.map do |usage|
        message = turn.find { |candidate| candidate.id == usage.message_id }
        before = messages.reverse.find { |candidate| candidate.created_at < message.created_at }
        failed = usage.status == USAGE_FAILED
        # A call starts once what came before it was finished, which for a tool result is when it was filled in.
        Trace.span(
          key: "model-#{usage.id}", kind: KIND_MODEL, title: "Model call", started_at: before&.updated_at || message.created_at,
          ended_at: [ usage.updated_at, message.updated_at ].max, tone: failed ? IncidentProcess::TONE_BAD : IncidentProcess::TONE_INFO,
          detail: failed ? "#{usage.status} · #{usage.model}" : usage_detail(usage),
          facts: [
            [ "Model", "#{usage.provider} #{usage.model}" ], [ "Status", usage.status ], [ "Input tokens", usage.input_tokens ],
            [ "Read from cache", usage.cache_read_tokens ], [ "Written to cache", usage.cache_write_tokens ],
            [ "Thinking tokens", usage.thinking_tokens ], [ "Output tokens", usage.output_tokens ],
            [ "Cost", Money.dollars((usage.total_cost.to_f * Money::MICROS_PER_DOLLAR).round) ], [ "Stopped because", message.finish_reason ]
          ],
          body: -> { message_text(message) }
        )
      end
    end

    def tool_spans(turn)
      ids = turn.map(&:id)
      calls.select { |call| ids.include?(call.message_id) }.map do |call|
        asked = messages.find { |message| message.id == call.message_id }
        result = messages.find { |message| message.id == call.result_id }
        # The result is saved as the tool starts and filled in when it answers, so those two times are the call.
        started = result&.created_at || asked.updated_at
        Trace.span(
          key: "call-#{call.id}", kind: KIND_TOOL, title: call.name, started_at: started, ended_at: result&.updated_at,
          tone: call.failed ? IncidentProcess::TONE_BAD : IncidentProcess::TONE_OK,
          detail: [ call.failed ? "failed" : "done", ("approval #{call.approval}" if call.approval), Trace.seconds(started, result&.updated_at),
                    Trace.size(result&.content) ].compact.join(" · "),
          facts: [ [ "Asked with", call.arguments.presence&.to_json ], [ "Approval", call.approval ], [ "Returned", Trace.size(result&.content) ],
                   [ "Run by the provider", ("yes" if call.remote) ] ],
          body: result && -> { result.content.to_s }
        )
      end
    end

    def reply_span(turn)
      reply = turn.reverse.find { |message| message.role == Chat::Message::ROLE_ASSISTANT && !message.nudge && message.content.present? }
      return nil unless reply

      # A reply is saved as it starts streaming, and finished when it was last written.
      Trace.span(key: "reply-#{reply.id}", kind: KIND_REPLY, title: "Replied", started_at: reply.updated_at,
                 detail: reply.content.to_s.squish.truncate(140), body: -> { reply.content.to_s })
    end

    def run_spans(from, to)
      conversation.investigations.select { |run| run.created_at.between?(from, to + 1.minute) }.map do |run|
        Trace.span(key: "run-#{run.id}", kind: KIND_RUN, title: "Started a run", started_at: run.created_at, tone: IncidentProcess::TONE_INFO,
                   detail: "#{run.question || run.incident&.identifier} · #{HalonRuns.ending(run.status, run.error_summary)}", run_id: run.id)
      end
    end

    def usages
      @usages ||= conversation.chat ? RubyLLM::ActiveRecord::Usage.where(chat_type: Chat.name, chat_id: conversation.chat.id).order(:created_at).to_a : []
    end

    def calls
      @calls ||= conversation.chat ? conversation.chat.tool_calls.order(:created_at).to_a : []
    end

    def usage_detail(usage)
      input = usage.input_tokens.to_i + usage.cache_read_tokens.to_i
      cached = usage.cache_read_tokens.to_i.positive? ? ", #{Trace.tokens(usage.cache_read_tokens)} cached" : ""
      "#{Trace.tokens(input)} in#{cached} · #{Trace.tokens(usage.output_tokens)} out · #{Money.dollars((usage.total_cost.to_f * Money::MICROS_PER_DOLLAR).round)}"
    end

    def message_text(message)
      requested = calls.select { |call| call.message_id == message.id }.map { |call| "#{call.name} #{call.arguments.to_json}" }
      [
        ("Thinking\n#{message.thinking_text}" if message.thinking_text.present?),
        ("Said\n#{message.content}" if message.content.present?),
        ("Asked for\n#{requested.join("\n")}" if requested.any?)
      ].compact.join("\n\n")
    end
  end
end
