# What keeps a workflow from running away: how many runs it starts an hour (its most runs per hour, 100 unless someone
# sets another), and one live run per subject when it names one (such as one per service). A run a trigger would have
# started past the hour's limit is skipped and counted (Workflow::SkippedRun), so its page says how many and when. A
# run's spending ceiling is cost_cap_cents, which has no default.
module Workflow::Limits
  extend ActiveSupport::Concern

  RUNS_PER_HOUR = (1..1_000)
  DEFAULT_RUNS_PER_HOUR = 100
  SUBJECT_KEY_LIMIT = 200

  included do
    has_many :skipped_runs, class_name: "Workflow::SkippedRun", dependent: :delete_all, inverse_of: :workflow

    validates :runs_per_hour, numericality: { only_integer: true, in: RUNS_PER_HOUR }
    validates :subject_key, length: { maximum: SUBJECT_KEY_LIMIT }, allow_nil: true
    validate :subject_key_reads_the_run
  end

  # Why it cannot start another run this hour, or nil. Test runs do not count.
  def rate_blocked_reason(now: Time.current)
    started = runs.where(test: false, created_at: (now - 1.hour)..).count
    return if started < runs_per_hour

    "#{name} already started #{started} #{'run'.pluralize(started)} in the last hour, which is as many as it allows, so this one did not start."
  end

  # A run a trigger would have started past the hour's limit, counted in the hour it was skipped in.
  def run_skipped!(at: Time.current) = Workflow::SkippedRun.count!(self, at: at)

  # The hours runs were skipped in over the last week, newest first, as its page shows them.
  def recent_skips(now = Time.current) = skipped_runs.recent(now).to_a

  def skipped_runs_sentence(skips = recent_skips)
    count = skips.sum(&:count)
    return if count.zero?

    "#{count} #{'run'.pluralize(count)} #{count == 1 ? 'was' : 'were'} skipped in the last week because it had already started as many runs in the hour before as it allows."
  end

  # The subject a run is about, filled from what started it, so one live run per subject is kept. nil without one.
  def subject_for(inputs:, trigger_payload:)
    return if subject_key.blank?

    filled = Workflow::Version.filled(subject_key, Workflow::Version::ROOT_INPUTS => inputs.to_h, Workflow::Version::ROOT_TRIGGER => trigger_payload.to_h)
    filled.to_s.strip.presence
  end

  private

  def subject_key_reads_the_run
    return if subject_key.blank?

    roots = Workflow::Version.references_in(subject_key).map { |path| path.split(".").first }
    return errors.add(:subject_key, "names what a run is about with a reference such as {{inputs.service}}") if roots.empty?

    allowed = [ Workflow::Version::ROOT_INPUTS, Workflow::Version::ROOT_TRIGGER ]
    errors.add(:subject_key, "reads only the inputs or the trigger, which a run knows when it starts") unless roots.all? { |root| allowed.include?(root) }
  end
end
