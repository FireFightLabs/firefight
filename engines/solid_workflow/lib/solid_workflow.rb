require "solid_workflow/version"
require "solid_workflow/engine"

module SolidWorkflow
  extend self

  mattr_accessor :queue_name, default: :workflows
  mattr_accessor :stuck_workflow_threshold, default: 5.minutes
  mattr_accessor :orphaned_step_threshold, default: 10.minutes
  mattr_accessor :max_default_attempts, default: 5
  mattr_accessor :default_backoff, default: "exponential"

  # Error classes (as strings) that should never be retried — the next
  # attempt produces the same outcome. Host apps append their own via an
  # initializer; the engine ships only generic Ruby/AR classes.
  mattr_accessor :terminal_error_classes, default: %w[
    ActiveRecord::RecordNotFound
    ActiveRecord::RecordInvalid
    ArgumentError
    NoMethodError
    TypeError
  ]

  def configure
    yield self
  end
end
