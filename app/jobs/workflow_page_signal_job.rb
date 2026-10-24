# Sends the trailing signal for changes Workflow::LiveDelivery held back inside its window.
class WorkflowPageSignalJob < ApplicationJob
  queue_as :events

  def perform(workflow_id, part)
    Workflow::LiveDelivery.trailing(workflow_id: workflow_id, part: part)
  end
end
