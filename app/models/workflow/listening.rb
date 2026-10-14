# Which workflows something happening starts. A workflow listens while it is switched on and its live version's trigger
# is of the event's kind. It hears an event when what happened is among what its trigger chose (such as the severity
# changing), every condition holds of the event (the rule engine's, Policy::Conditions), and it did not cause the event
# itself, so a change a workflow makes never starts that same workflow again.
module Workflow::Listening
  extend ActiveSupport::Concern

  # The trigger's own choice among what happened, for a kind whose events are tagged.
  KEY_CHANGES = "changes".freeze
  # The label an issue gets that starts it, besides being assigned. An event about labels added is tagged with each, as
  # LABEL_TAG and the label's name in lower case, so a label is matched whatever its case.
  KEY_LABEL = "label".freeze
  LABEL_TAG = "label:".freeze

  included do
    scope :listening, lambda { |workspace, kind|
      enabled.where(workspace: workspace).joins(:live_version)
             .where("workflow_versions.trigger ->> ? = ?", Workflow::Trigger::KEY_KIND, kind.to_s)
    }
  end

  def hears?(event)
    trigger = live_version&.trigger.to_h
    return false unless trigger[Workflow::Trigger::KEY_KIND] == event.kind
    return false if caused?(event)
    return false unless chosen?(trigger, event)
    return false unless labelled?(trigger, event)

    Policy::Conditions.all?(Workflow::Trigger.conditions(trigger), event.context)
  end

  private

  def caused?(event)
    actor = event.actor.to_h
    agent_id.present? && actor["type"] == Agent.name && actor["id"].to_s == agent_id.to_s
  end

  def chosen?(trigger, event)
    return true unless trigger.key?(KEY_CHANGES)

    (Array(trigger[KEY_CHANGES]).map(&:to_s) & Array(event.tags).map(&:to_s)).any?
  end

  # An event about labels added is heard only by a trigger that names one of them. Any other event is not about labels.
  def labelled?(trigger, event)
    added = Array(event.tags).map(&:to_s).select { |tag| tag.start_with?(LABEL_TAG) }
    return true if added.empty?

    wanted = trigger[KEY_LABEL].to_s.strip.downcase
    wanted.present? && added.include?("#{LABEL_TAG}#{wanted}")
  end
end
