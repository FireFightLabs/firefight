# When a workflow with a Schedule or Once at trigger runs next, kept on the workflow so a sweep each minute finds what
# is due. Taking a due workflow moves its time on in one statement naming the time it was due at, so two sweeps never
# both start it. A one off has no next time once it ran. A workflow switched off, or with nothing live, has none.
module Workflow::Scheduling
  extend ActiveSupport::Concern

  included do
    scope :due, ->(now = Time.current) { enabled.where.not(live_version_id: nil).where(next_run_at: ..now) }
    scope :given_up_unrecorded, -> { where.not(given_up_at: nil).where.not(live_version_id: nil) }
  end

  # Works out its next time from now, or clears it.
  def schedule!(from: Time.current)
    following = (Workflow::Trigger::Schedule.next_after(live_version.trigger, from) if enabled? && live_version)
    self.class.where(id: id).update_all(next_run_at: following, updated_at: Time.current)
    self.next_run_at = following
  end

  # Takes it for the time it was due at and moves its next time on. Answers that time, or nil when another sweep took it.
  def claim_due!(now = Time.current)
    due_at = next_run_at
    return nil unless due_at && due_at <= now && live_version

    following = Workflow::Trigger::Schedule.next_after(live_version.trigger, now)
    taken = self.class.enabled.where(id: id, next_run_at: due_at).update_all(next_run_at: following, updated_at: now) == 1
    return nil unless taken

    self.next_run_at = following
    due_at
  end

  # Gives back a time claim_due! took when starting it broke, so the next sweep tries that time again, unless something
  # moved its next time since. Its start key is that time's, so a run that was made before it broke is never made twice.
  def release_due!(due_at)
    self.class.where(id: id, next_run_at: next_run_at).update_all(next_run_at: due_at, updated_at: Time.current)
  end

  # Keeps a time whose giving up broke before it was recorded, so the next sweep records it. Its next time is left as
  # it is, since the time stays given up.
  def keep_given_up!(due_at)
    self.class.where(id: id).update_all(given_up_at: due_at, updated_at: Time.current)
  end

  # Once it is recorded, unless a later time was kept meanwhile.
  def given_up_recorded!(due_at)
    self.class.where(id: id, given_up_at: due_at).update_all(given_up_at: nil, updated_at: Time.current)
  end

  # Said when its next time lands in a freeze window, since a change it makes then waits or stops as it says.
  def freeze_warning
    window = next_run_at && live_version&.steps_that_change&.any? && Workspace::FreezeWindows.covering(workspace, next_run_at)
    return unless window

    action = waits_out_freezes? ? "a change it makes waits for it to end" : "a change it makes stops the run"
    "Its next run lands in the #{window.name} freeze, so #{action}."
  end

  # Why its trigger could not start a run when it was due, kept for its page until a run starts.
  def trigger_refused!(reason, at: Time.current)
    self.class.where(id: id).update_all(trigger_refusal: reason, trigger_refused_at: at, updated_at: at)
  end

  def trigger_started!
    self.class.where(id: id).where.not(trigger_refusal: nil).update_all(trigger_refusal: nil, trigger_refused_at: nil, updated_at: Time.current)
  end
end
