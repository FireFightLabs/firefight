module Operator
  # One scenario in a chat bench run: its four scores, what the replay answered, what the judge said and what took
  # marks away, and its total in the run before on the same model. A scenario holds no customer data.
  class HalonBenchScenarioSerializer < BaseSerializer
    object_as :entry

    type :string
    def id = result.id

    type :string
    def scenario = result.scenario

    type :string
    def title = result.title

    type Conversation::BenchResult::STATUSES.map(&:inspect).join(" | ")
    def status = result.status

    type :number, optional: true
    def total = result.total

    type :number, optional: true
    def previous_total = entry.previous_total

    type :number, optional: true
    def change = entry.change

    type :number, optional: true
    def right = result.right

    type :number, optional: true
    def moved_forward = result.moved_forward

    type :number, optional: true
    def asked_when_needed = result.asked_when_needed

    type :number, optional: true
    def cost = result.cost

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

    private

    def result = entry.result
  end
end
