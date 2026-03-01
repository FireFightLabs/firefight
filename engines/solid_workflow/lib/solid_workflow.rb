require "solid_workflow/version"
require "solid_workflow/engine"

module SolidWorkflow
  extend self

  mattr_accessor :queue_name, default: :workflows
  mattr_accessor :stuck_workflow_threshold, default: 5.minutes
  mattr_accessor :orphaned_step_threshold, default: 10.minutes
  mattr_accessor :max_default_attempts, default: 5
  mattr_accessor :default_backoff, default: "exponential"

  def configure
    yield self
  end
end
