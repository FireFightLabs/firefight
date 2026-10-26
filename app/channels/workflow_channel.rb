# An open workflow page, told which part of it changed (Workflow::LiveDelivery) so it reads that part again. The signal
# carries no workflow data, the page reads it through the same authorized request as always. Nothing said before the
# page listened is said again, so once its subscription is confirmed, and so it hears every say, the page asks to catch
# up and is told each part that changed since it was read (read_at, which the page was given as liveReadAt), and every
# part when that cannot be told.
class WorkflowChannel < ApplicationCable::Channel
  READ_AT_PARAM = "read_at"
  CATCH_UP_ACTION = "catch_up"

  def self.stream_name(workflow_id) = "workflow:#{workflow_id}"

  def subscribed
    workflow = Workflow.find_by(id: params[:id])
    return reject unless workflow&.watchable_by?(current_user)

    @workflow_id = workflow.id
    stream_from self.class.stream_name(workflow.id)
  end

  def catch_up
    Workflow::LiveDelivery.changed_since(@workflow_id, read_at).each { |part| transmit({ part: part }) }
  end

  private

  def read_at = Float(params[READ_AT_PARAM], exception: false)
end
