module Operator
  # One trace span, without its content. The content loads when the span is opened.
  class TraceSpanSerializer < BaseSerializer
    object_as :span

    KIND_UNION = Operator::Trace::KINDS.map(&:inspect).join(" | ")
    TONE_UNION = Operator::IncidentProcess::TONES.map(&:inspect).join(" | ")

    type :string
    def key = span.key

    type KIND_UNION
    def kind = span.kind

    type TONE_UNION
    def tone = span.tone

    type :string
    def title = span.title

    type :string, optional: true
    def detail = span.detail

    type :string
    def started_at = span.started_at.utc.iso8601(3)

    type :string, optional: true
    def ended_at = span.ended_at&.utc&.iso8601(3)

    type "{ label: string; value: string }[]"
    def facts = span.facts.map { |label, value| { label: label, value: value.to_s } }

    type :boolean
    def has_body = span.body?

    type :string, optional: true
    def run_id = span.run_id
  end
end
