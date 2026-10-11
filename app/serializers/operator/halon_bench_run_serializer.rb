module Operator
  # A chat bench run with how many scenarios it scored, the mean of each score over them, quality and cost apart, and
  # how far apart its repeats lay.
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

    # Why the run stopped before its scenarios ran, such as its AI account refusing it.
    type :string, optional: true
    def stopped_reason = row.run.stopped_reason

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

    type :number, optional: true
    def cited = row.means[:cited]

    # The mean of right, moved forward and asked when needed, quality apart from cost.
    type :number, optional: true
    def quality = row.quality

    # How often each scenario is replayed.
    type :number
    def repeats = row.run.repeats

    # How far apart the run's whole passes lay, nil with fewer than two.
    type :number, optional: true
    def spread = row.spread

    # Scenarios whose repeats lay within the agreement of each other, of those replayed more than once.
    type :number
    def agreeing = row.agreeing

    type :number
    def repeated = row.repeated

    type :number
    def agreement = Conversation::BenchRun::AGREEMENT

    # What Halon's own model calls cost.
    type :number
    def spent_micros = row.spent_micros

    type :number
    def judge_spent_micros = row.judge_spent_micros

    # What the run may spend on Halon and the judge together, nil for a run with no cap.
    type :number, optional: true
    def budget_micros = row.run.budget_micros

    type :string
    def created_at = row.run.created_at.utc.iso8601

    type :string, optional: true
    def finished_at = row.run.finished_at&.utc&.iso8601
  end
end
