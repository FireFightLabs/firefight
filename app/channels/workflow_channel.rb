# An open workflow page, told which part of it changed (Workflow::LiveDelivery) so it reads that part again. The signal
# carries no workflow data, the page reads it through the same authorized request as always.
class WorkflowChannel < ApplicationCable::Channel
  def self.stream_name(workflow_id) = "workflow:#{workflow_id}"

  def subscribed
    workflow = Workflow.find_by(id: params[:id])
    return reject unless workflow&.watchable_by?(current_user)

    stream_from self.class.stream_name(workflow.id)
  end
end
