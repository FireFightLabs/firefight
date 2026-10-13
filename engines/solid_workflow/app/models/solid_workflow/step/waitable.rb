module SolidWorkflow
  class Step < Record
    # A step that waits is parked rather than held by a worker: a delay until its time, a wait for an event until its
    # signal or its deadline, a for each or a sub workflow until a child it started ends. Waking moves it back to
    # pending in one guarded update, so two wakes, or a wake racing the sweeper, move it once. A wake that lands while
    # the step is still running is counted, and the step wakes itself as soon as it parks, so it is never lost.
    module Waitable
      extend ActiveSupport::Concern

      class_methods do
        # Hands the payload to every step waiting on the key and wakes it. Returns how many were waiting.
        def signal!(key, payload = {})
          waiting.where(signal_key: key).find_each.count do |step|
            kept = step.workflow.workflow_klass.clean(payload.to_h.deep_stringify_keys, workflow: step.workflow, step: step)
            delivered = where(id: step.id, status: :waiting, signal_key: key, signal_payload: nil)
                        .update_all(signal_payload: kept, updated_at: Time.current) == 1
            next false unless delivered

            step.reload
            step.workflow.record_event(SolidWorkflow::Events::Step::SIGNALLED, step: step, signal: key)
            step.wake!(reason: "signal")
            true
          end
        end
      end

      def park!(park, seen_wakes:)
        moved = SolidWorkflow::Step.where(id: id, status: :running).update_all(
          status: :waiting, run_at: park.wake_at, signal_key: park.signal_key, claimed_by: nil, timeout_at: nil, updated_at: Time.current
        )
        return false unless moved == 1

        reload
        workflow.record_event(SolidWorkflow::Events::Step::WAITING, step: self, until: park.wake_at&.iso8601, signal: park.signal_key)
        SolidWorkflow::WakeJob.set(wait_until: park.wake_at).perform_later(id) if park.wake_at
        wake!(reason: "woken_while_running") if wake_requests > seen_wakes
        true
      end

      def wake!(reason:)
        SolidWorkflow::Step.where(id: id).update_all("wake_requests = wake_requests + 1")
        moved = SolidWorkflow::Step.where(id: id, status: :waiting).update_all(status: :pending, run_at: nil, updated_at: Time.current)
        reload
        return false unless moved == 1

        workflow.record_event(SolidWorkflow::Events::Step::WOKEN, step: self, reason: reason)
        workflow.enqueue_next_steps_later
        true
      end

      # Woken by its time only once the time came, so an early job or a clock a little behind leaves it parked.
      def wake_if_due!
        return false unless waiting? && run_at && run_at <= Time.current

        wake!(reason: "time")
      end
    end
  end
end
