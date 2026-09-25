module Operator
  # What a trace is drawn from: spans on one clock, in groups. A run is one group, a chat is one group per turn, so each
  # turn has its own clock. A span's body, which can be large and is the customer's data, is read one at a time by key.
  module Trace
    KIND_JOB = "job".freeze
    KIND_FACTS = "facts".freeze
    KIND_MODEL = "model".freeze
    KIND_TOOL = "tool".freeze
    KIND_THEORY = "theory".freeze
    KIND_CHECK = "check".freeze
    KIND_ANSWER = "answer".freeze
    KIND_STOP = "stop".freeze
    KIND_POST = "post".freeze
    KIND_PLATFORM = "platform".freeze
    KIND_VERDICT = "verdict".freeze
    KIND_ASK = "ask".freeze
    KIND_REPLY = "reply".freeze
    KIND_RUN = "run".freeze
    KINDS = [
      KIND_JOB, KIND_FACTS, KIND_MODEL, KIND_TOOL, KIND_THEORY, KIND_CHECK, KIND_ANSWER, KIND_STOP, KIND_POST,
      KIND_PLATFORM, KIND_VERDICT, KIND_ASK, KIND_REPLY, KIND_RUN
    ].freeze

    # The query parameter that names the opened span, and the prop its content comes back in.
    SPAN_PARAM = "span".freeze
    BODY_PROP = "spanBody".freeze

    # A body past this is cut, and says so.
    BODY_LIMIT = 100_000

    # facts are label and value pairs for the selected span. body is a block that reads the span's content when it is
    # opened. run_id names a run the span opens.
    Span = Data.define(:key, :kind, :tone, :title, :detail, :started_at, :ended_at, :facts, :body, :run_id) do
      def body? = !body.nil?

      def read_body = body && Trace.body_text(body.call)
    end
    Group = Data.define(:key, :title, :started_at, :ended_at, :spans)

    def self.span(key:, kind:, title:, started_at:, tone: IncidentProcess::TONE_OK, detail: nil, ended_at: nil, facts: [], body: nil, run_id: nil)
      Span.new(key:, kind:, tone:, title:, detail:, started_at:, ended_at:, facts: facts.reject { |_label, value| value.blank? }, body:, run_id:)
    end

    # What people said comes after the work, days later at times, so it is listed last and does not stretch the clock.
    AFTERWARDS = [ KIND_VERDICT ].freeze

    def self.build_group(key, title, spans)
      spans = spans.select(&:started_at).sort_by { |span| [ AFTERWARDS.include?(span.kind) ? 1 : 0, span.started_at, span.key ] }
      timed = spans.reject { |span| AFTERWARDS.include?(span.kind) }
      Group.new(key:, title:, started_at: timed.map(&:started_at).min, ended_at: timed.filter_map { |span| span.ended_at || span.started_at }.max, spans:)
    end

    # Bodies are built only when asked for, since a run's tool output alone can run to megabytes.
    def self.body_text(value)
      text = value.is_a?(String) ? value : JSON.pretty_generate(value)
      text.length > BODY_LIMIT ? "#{text.first(BODY_LIMIT)}\n\n[Cut at #{BODY_LIMIT} of #{text.length} characters]" : text
    end

    def self.tokens(count)
      count.to_i >= 1000 ? "#{(count / 1000.0).round(1)}k" : count.to_i.to_s
    end

    def self.seconds(from, to)
      "#{(to - from).round(1)} s" if from && to
    end

    def self.size(text)
      ActiveSupport::NumberHelper.number_to_human_size(text.to_s.bytesize) if text.present?
    end
  end
end
