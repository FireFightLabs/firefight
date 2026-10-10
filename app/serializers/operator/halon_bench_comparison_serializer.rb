module Operator
  # Two chat bench runs side by side: the mean of each score over the scenarios both scored, whether the newer one
  # dropped by more than the noise, and every scenario's total on each side.
  class HalonBenchComparisonSerializer < BaseSerializer
    object_as :comparison

    ROW = "{ scenario: string; title: string; base: number | null; head: number | null; delta: number | null }[]".freeze
    SIDES = "{ base: number | null; head: number | null }".freeze

    type :number
    def tolerance = Conversation::BenchComparison::TOLERANCE

    type :boolean
    def dropped = comparison.dropped?

    type :boolean
    def comparable = comparison.comparable?

    type :boolean
    def failed = comparison.failed?

    type :number
    def shared = comparison.shared.size

    type SIDES
    def total = { base: comparison.base_total, head: comparison.head_total }

    type "Record<#{Conversation::BenchScore.dimensions.map { |name| name.to_s.camelize(:lower).inspect }.join(' | ')}, #{SIDES}>"
    def dimensions
      Conversation::BenchScore.dimensions.to_h do |name|
        [ name.to_s.camelize(:lower), { base: comparison.dimension(:base, name), head: comparison.dimension(:head, name) } ]
      end
    end

    type ROW
    def rows
      comparison.rows.map do |row|
        { scenario: row.scenario, title: row.title, base: row.base&.total, head: row.head&.total, delta: row.delta }
      end
    end
  end
end
