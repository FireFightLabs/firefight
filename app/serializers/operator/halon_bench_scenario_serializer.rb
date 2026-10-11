module Operator
  # One scenario in a chat bench run, with the mean of its scores over its repeats, how far apart their totals lay, its
  # total in the run before on the same model, and each replay with what it answered and what took marks away. A
  # scenario holds no customer data.
  class HalonBenchScenarioSerializer < BaseSerializer
    object_as :entry

    type :string
    def scenario = tally.scenario

    type :string
    def title = tally.title

    type Conversation::BenchResult::STATUSES.map(&:inspect).join(" | ")
    def status = tally.status

    type :number, optional: true
    def total = tally.total

    type :number, optional: true
    def quality = tally.quality

    # Highest total less lowest over its repeats, nil with fewer than two scored.
    type :number, optional: true
    def spread = tally.spread

    type :boolean
    def agrees = tally.agrees?

    type :number, optional: true
    def previous_total = entry.previous_total

    type :number, optional: true
    def change = entry.change

    type :number, optional: true
    def right = tally.score&.right

    type :number, optional: true
    def moved_forward = tally.score&.moved_forward

    type :number, optional: true
    def asked_when_needed = tally.score&.asked_when_needed

    type :number, optional: true
    def cost = tally.score&.cost

    type :number, optional: true
    def cited = tally.score&.cited

    type :number
    def spent_micros = tally.spent_micros

    has_many :replays, serializer: HalonBenchReplaySerializer

    private

    def tally = entry.tally
  end
end
