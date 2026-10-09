module Operator
  # One rated answer in a regression run: what the team said of it, what the replay answered, and how it did before.
  class HalonRegressionCaseSerializer < BaseSerializer
    object_as :entry

    STATUS_UNION = Investigation::RegressionResult::STATUSES.map(&:inspect).join(" | ")

    type :string
    def id = entry.result.id

    type STATUS_UNION
    def status = entry.result.status

    type STATUS_UNION, optional: true
    def previous_status = entry.previous_status

    type :boolean
    def newly_failing = entry.newly_failing?

    type Investigation::RegressionResult::EXPECTED.map(&:inspect).join(" | ")
    def expected = entry.result.expected

    type :string
    def workspace_name = original.workspace.name

    type :string
    def label = original.label

    type :string
    def original_id = original.id

    type :string, optional: true
    def replay_id = entry.result.replay_id

    type :string
    def rated_answer = entry.result.finding.summary

    type :string, optional: true
    def answer = entry.result.answer

    type :string, optional: true
    def reason = entry.result.reason

    type :number
    def spent_micros = entry.result.spent_micros

    private

    def original = entry.result.finding.investigation
  end
end
