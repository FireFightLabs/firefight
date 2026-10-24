# Tells open workflow pages which part of them changed (Workflow::LiveSignal), over WorkflowChannel. A busy run moves
# its steps many times a second, so each workflow and part is said at most once per WINDOW, as Incident::LiveDelivery
# does for an incident's page. The first change held back books one trailing say (WorkflowPageSignalJob) for after the
# window, which covers every change made before it runs.
class Workflow::LiveDelivery
  WINDOW = 1.second

  # Runs after the change committed, so a cache, queue or cable that is down is logged and never reaches whoever made
  # the change. An open page reads every part again when its socket next connects.
  def self.changed(workflow_id:, part:)
    return say(workflow_id, part) if Rails.cache.write(gate_key(workflow_id, part), true, unless_exist: true, expires_in: WINDOW)
    return unless Rails.cache.write(trailing_key(workflow_id, part), true, unless_exist: true, expires_in: WINDOW)

    WorkflowPageSignalJob.set(wait: WINDOW).perform_later(workflow_id, part)
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_page.signal_failed", workflow_id: workflow_id, part: part, error: error.class.name, message: error.message }.to_json)
  end

  # The trailing say goes through the gate too, with its own booking cleared first so a held back say books the next.
  def self.trailing(workflow_id:, part:)
    Rails.cache.delete(trailing_key(workflow_id, part))
    changed(workflow_id: workflow_id, part: part)
  end

  def self.say(workflow_id, part)
    ActionCable.server.broadcast(WorkflowChannel.stream_name(workflow_id), { part: part })
  end

  def self.gate_key(workflow_id, part) = "workflow_page/#{workflow_id}/#{part}"

  def self.trailing_key(workflow_id, part) = "workflow_page/#{workflow_id}/#{part}/trailing"
end
