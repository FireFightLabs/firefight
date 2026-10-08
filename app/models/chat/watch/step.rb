# One thing a watch follows, read through one capability as the person who asked: a run in a resource's history (a CI
# run, a build, a deploy), or a reading such as a resource's status that says when it is done or failed. Each milestone
# is claimed by one guarded update, so it is reported once.
class Chat::Watch::Step < ApplicationRecord
  STATUS_WAITING = "waiting"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  # It could not be read any more, such as a permission taken away, so the watch no longer follows it.
  STATUS_UNFOLLOWABLE = "unfollowable"
  STATUSES = [ STATUS_WAITING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE ].freeze
  OVER = [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE ].freeze
  # Running this much longer than usual is worth saying, once.
  SLOW_AFTER = 1.5
  SLOW_AT_LEAST = 2.minutes
  # A run that started this long before the watch is still the one asked about, since a person asks after starting it.
  STARTED_BEFORE_WATCH = 10.minutes
  STATE_LIMIT = 1_000

  belongs_to :watch, class_name: "Chat::Watch", inverse_of: :steps
  belongs_to :integration_environment, optional: true

  validates :status, inclusion: { in: STATUSES }

  def history? = capability == Integrations::Capabilities::HISTORY

  def spec = Integrations::Capabilities.spec(capability)

  def over? = OVER.include?(status)

  def running? = status == STATUS_RUNNING

  # The run this step follows among those a history read found: the one it already follows, the one the person named,
  # or the first of its name that started around or after the watch began.
  def run_among(runs)
    return runs.find { |run| run.id.to_s == followed_run_id } if followed_run_id.present?
    return runs.find { |run| run.named?(run_ref) } if run_ref.present?

    since = watch.created_at - STARTED_BEFORE_WATCH
    runs.select { |run| run.called?(run_name) && run.started_at && run.started_at >= since && !finished_before_watch?(run) }
        .min_by(&:started_at)
  end

  # Whether it ran this long past its usual time and has not said so yet.
  def slow?(now = Time.current)
    return false unless running? && started_at && usual_seconds.to_i.positive? && slow_told_at.nil?

    elapsed = now - started_at
    elapsed > usual_seconds * SLOW_AFTER && elapsed > usual_seconds + SLOW_AT_LEAST
  end

  # The run was seen going. True once, for whoever saw it first.
  def started!(run_id:, at:, url: nil)
    claim(started_told_at: nil) { { status: STATUS_RUNNING, followed_run_id: run_id, started_at: at || Time.current, run_url: url, started_told_at: Time.current } }
  end

  # The run or reading is over. True once, for whoever saw it first.
  def finished!(status, reason: nil, at: nil, run_id: nil, url: nil, started: nil)
    claim(finished_told_at: nil) do
      { status: status, reason: reason&.truncate(STATE_LIMIT), finished_at: at || Time.current, finished_told_at: Time.current,
        followed_run_id: run_id || followed_run_id, run_url: url || run_url, started_at: started_at || started || at }
    end
  end

  def slow_told! = claim(slow_told_at: nil) { { slow_told_at: Time.current } }

  def unfollowable!(reason) = finished!(STATUS_UNFOLLOWABLE, reason: reason)

  # What a read showed last, kept so a check that sees nothing new asks no model.
  def seen!(digest:, state:)
    update_columns(last_digest: digest, last_state: state.to_s.truncate(STATE_LIMIT), updated_at: Time.current)
  end

  def seconds_taken
    return unless started_at && finished_at

    (finished_at - started_at).round
  end

  private

  def finished_before_watch?(run) = run.finished? && run.finished_at && run.finished_at < watch.created_at

  def claim(unset)
    moved = self.class.where(id: id, **unset).update_all(**yield, updated_at: Time.current)
    reload
    moved == 1
  end
end
