module Operator
  # A chat bench run with how many scenarios it scored and the mean of each score.
  class HalonBenchRunSerializer < BaseSerializer
    object_as :row

    type :string
    def id = row.run.id

    type Conversation::BenchRun::TRIGGERS.map(&:inspect).join(" | ")
    def trigger = row.run.trigger

    type Conversation::BenchRun::STATUSES.map(&:inspect).join(" | ")
    def status = row.run.status

    type :string
    def prompt_version = row.run.prompt_version

    type :string
    def model = row.run.model

    type :string, optional: true
    def label = row.run.label

    type :string, optional: true
    def started_by = row.run.started_by&.then { |user| user.name.presence || user.email }

    type :number
    def scored = row.scored

    type :number
    def errored = row.errored

    type :number
    def pending = row.pending

    # Nil until a scenario is scored.
    type :number, optional: true
    def total = row.total

    type :number, optional: true
    def right = row.means[:right]

    type :number, optional: true
    def moved_forward = row.means[:moved_forward]

    type :number, optional: true
    def asked_when_needed = row.means[:asked_when_needed]

    type :number, optional: true
    def cost = row.means[:cost]

    type :number
    def spent_micros = row.spent_micros

    type :string
    def created_at = row.run.created_at.utc.iso8601

    type :string, optional: true
    def finished_at = row.run.finished_at&.utc&.iso8601
  end
end
