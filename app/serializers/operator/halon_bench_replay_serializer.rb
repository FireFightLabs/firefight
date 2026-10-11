module Operator
  # One replay of a scenario in a chat bench run: its scores, what it answered, what the judge said and what took marks
  # away. A scenario holds no customer data.
  class HalonBenchReplaySerializer < BaseSerializer
    object_as :result

    type :string
    def id = result.id

    type :number
    def attempt = result.attempt

    type Conversation::BenchResult::STATUSES.map(&:inspect).join(" | ")
    def status = result.status

    type :number, optional: true
    def total = result.total

    type :number, optional: true
    def quality = result.quality

    type :number, optional: true
    def right = result.right

    type :number, optional: true
    def moved_forward = result.moved_forward

    type :number, optional: true
    def asked_when_needed = result.asked_when_needed

    type :number, optional: true
    def cost = result.cost

    type :number, optional: true
    def cited = result.cited

    type :number
    def spent_micros = result.spent_micros

    type :number
    def turns = result.turns

    type :number
    def calls = result.calls

    type :number
    def not_recorded = result.not_recorded

    type :number
    def confirmations = result.confirmations

    type :number
    def unneeded_asks = result.unneeded_asks

    type :string, optional: true
    def answer = result.answer

    type :string, optional: true
    def reason = result.reason

    type "string[]"
    def notes = result.notes
  end
end
