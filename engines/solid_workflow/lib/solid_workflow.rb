require "solid_workflow/version"
require "solid_workflow/engine"

module SolidWorkflow
  extend self

  mattr_accessor :queue_name, default: :workflows
  mattr_accessor :stuck_workflow_threshold, default: 5.minutes
  mattr_accessor :orphaned_step_threshold, default: 10.minutes
  mattr_accessor :max_default_attempts, default: 5
  mattr_accessor :default_backoff, default: "exponential"

  # Never retried, the next attempt gives the same outcome. Hosts append their own in an initializer.
  mattr_accessor :terminal_error_classes, default: %w[
    ActiveRecord::RecordNotFound
    ActiveRecord::RecordInvalid
    ArgumentError
    NoMethodError
    TypeError
    SolidWorkflow::InvalidDefinition
    SolidWorkflow::TimeLimitReached
    SolidWorkflow::SubWorkflowFailed
    SolidWorkflow::UnknownStepKind
    SolidWorkflow::Stopped
  ]

  def configure
    yield self
  end

  # Hands the payload to every step waiting for the key, such as "incident.resolved:<id>", and wakes it. Returns how
  # many steps it reached.
  def signal!(key, payload = {}) = SolidWorkflow::Step.signal!(key, payload)
end
