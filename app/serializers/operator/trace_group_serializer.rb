module Operator
  # A run, or one chat turn, with its own time axis.
  class TraceGroupSerializer < BaseSerializer
    object_as :group

    type :string
    def key = group.key

    type :string
    def title = group.title

    type :string, optional: true
    def started_at = group.started_at&.utc&.iso8601(3)

    type :string, optional: true
    def ended_at = group.ended_at&.utc&.iso8601(3)

    has_many :spans, serializer: TraceSpanSerializer
  end
end
