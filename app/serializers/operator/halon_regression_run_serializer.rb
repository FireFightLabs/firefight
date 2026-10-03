module Operator
  # A regression run with how many of its cases passed.
  class HalonRegressionRunSerializer < BaseSerializer
    object_as :row

    type :string
    def id = row.run.id

    type Investigation::RegressionRun::TRIGGERS.map(&:inspect).join(" | ")
    def trigger = row.run.trigger

    type Investigation::RegressionRun::STATUSES.map(&:inspect).join(" | ")
    def status = row.run.status

    type :string
    def prompt_version = row.run.prompt_version

    # Nil when the run used Halon's own model.
    type :string, optional: true
    def model = row.run.model

    type :string, optional: true
    def started_by = row.run.started_by&.then { |user| user.name.presence || user.email }

    type :number
    def passed = row.tally.passed

    type :number
    def failed = row.tally.failed

    type :number
    def errored = row.tally.errored

    type :number
    def pending = row.tally.pending

    type :number
    def skipped = row.tally.skipped

    type :number
    def total = row.tally.total

    type :string
    def created_at = row.run.created_at.utc.iso8601

    type :string, optional: true
    def finished_at = row.run.finished_at&.utc&.iso8601
  end
end
