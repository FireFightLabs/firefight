module SolidWorkflow
  class Error < StandardError; end

  # A definition the interpreter cannot run, named by its problems.
  class InvalidDefinition < Error; end

  # A step ran past its own timeout. Retried like any other failure while attempts remain.
  class StepTimedOut < Error; end

  # A step that waits ran out of its time limit. Never retried, since waiting again cannot end differently.
  class TimeLimitReached < Error; end

  # A sub workflow, or an item of a for each, ended without succeeding.
  class SubWorkflowFailed < Error; end

  # A Stop step ended the run as failed, saying why. Never retried, since stopping again ends the same way.
  class Stopped < Error; end

  # A step kind nothing runs.
  class UnknownStepKind < Error; end

  # A step took a route that means it did not get what it waited for, such as running out of time, and no step follows
  # that route, so the step fails with its reason. Never retried, since the route was already taken.
  class RouteFailed < Error; end

  # What a step that waits hands back instead of an output: wake it at a time, on a signal, or when a child it
  # started ends.
  Park = Data.define(:wake_at, :signal_key) do
    def initialize(wake_at: nil, signal_key: nil) = super
  end

  # An output together with the route the step took, which decides which of its edges carry on. failure is why taking
  # that route means the step did not get what it waited for (it failed or ran out of time). With no step on that
  # route the step fails with those words. With one, the run carries on there as on any route.
  Routed = Data.define(:output, :route, :failure) do
    def initialize(output:, route:, failure: nil) = super
  end

  # What a step hands back when it decided not to act, with why in words. It ends skipped, and the steps after it carry
  # on as after a step that succeeded.
  Skipped = Data.define(:reason, :output) do
    def initialize(reason:, output: {}) = super
  end
end
