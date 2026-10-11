module Operator
  # Two chat bench runs side by side: the mean of each score over the scenarios both scored, whether the newer one
  # dropped by more than the noise, and every scenario's total on each side with how far apart its repeats lay.
  class HalonBenchComparisonSerializer < BaseSerializer
    object_as :comparison

    ROW = "{ scenario: string; title: string; base: number | null; head: number | null; baseSpread: number | null; " \
          "headSpread: number | null; delta: number | null; noise: number }[]".freeze
    SIDES = "{ base: number | null; head: number | null }".freeze
    # The scores each side is compared on, quality first since it is three of them in one.
    COMPARED = [ :quality, *Conversation::BenchScore.dimensions ].freeze

    type :number
    def tolerance = Conversation::BenchComparison::TOLERANCE

    # What the totals have to drop by to count, the tolerance or the spread either run saw between its own passes.
    type :number
    def noise = comparison.noise

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

    type "Record<#{COMPARED.map { |name| name.to_s.camelize(:lower).inspect }.join(' | ')}, #{SIDES}>"
    def dimensions
      COMPARED.to_h do |name|
        [ name.to_s.camelize(:lower), { base: comparison.dimension(:base, name), head: comparison.dimension(:head, name) } ]
      end
    end

    type ROW
    def rows
      comparison.rows.map do |row|
        { scenario: row.scenario, title: row.title, base: row.base&.total, head: row.head&.total, baseSpread: row.base&.spread,
          headSpread: row.head&.spread, delta: row.delta, noise: row.noise }
      end
    end
  end
end
