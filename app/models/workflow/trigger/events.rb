# Something happening that a workflow's trigger may start on: an incident declared or changed, an alert, a notice Halon
# raised, an investigation that finished, a follow up or postmortem that changed, another workflow's run that failed.
# Where it happens says so with fire!, which, once the change is committed and only when a live workflow of that kind is
# switched on in the workspace, hands it to WorkflowEventJob. The job reads what the run's trigger data holds and starts
# a run of every workflow it matches, once per event (the event's key is part of the run's start key).
module Workflow::Trigger::Events
  # The event as the job hears it. subject is the record it is about. tags name what about it happened, such as the
  # severity changing, for a kind whose trigger chooses among them. actor is whoever caused it, so a workflow never starts
  # itself again with a change it made.
  Event = Data.define(:kind, :key, :payload, :context, :tags, :actor) do
    def initialize(tags: [], actor: nil, **) = super

    # The key a run it starts is opened under, which makes hearing it twice start it once.
    def start_key = "event:#{kind}:#{key}"
  end

  module_function

  # Says that something happened. details are plain values the job reads it with, beside the record it is about. It
  # never raises, since telling workflows is never allowed to stop what happened from finishing, such as an investigation
  # closing or a failed run being said, so a failure here is logged and the event goes unheard.
  def fire!(workspace, kind, key:, subject:, details: {}, actor: nil)
    return unless listened?(workspace, kind)

    actor_ref = actor && { "type" => actor.class.name, "id" => actor.id }
    ActiveRecord.after_all_transactions_commit do
      WorkflowEventJob.perform_later(workspace.id, kind, key.to_s, subject, details.to_h.deep_stringify_keys, actor_ref)
    rescue StandardError => error
      unheard(workspace, kind, error)
    end
  rescue StandardError => error
    unheard(workspace, kind, error)
  end

  def unheard(workspace, kind, error)
    Rails.logger.error({ event: "workflow_trigger.unheard", workspace_id: workspace.id, kind: kind, error: error.class.name, message: error.message }.to_json)
  end

  # Whether any workflow of the workspace starts on the kind, which keeps the job from being asked about every event.
  def listened?(workspace, kind)
    Workflow.listening(workspace, kind).exists?
  end
end
