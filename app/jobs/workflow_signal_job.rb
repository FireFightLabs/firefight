# Wakes every workflow step waiting on something that just happened, such as an investigation a step started finishing.
class WorkflowSignalJob < ApplicationJob
  queue_as :default

  def perform(key, payload = {})
    DefinedWorkflow.signal!(key, payload)
  end
end
