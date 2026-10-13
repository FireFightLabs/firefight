# How an edit reads to a person: the toast that says it happened, the line in a version's history that says who did it,
# and the line a suggestion of Halon's is shown with. A step is named by its title, the name later steps refer to it by
# written as words, kept on the edit when it was made so a step removed since is still named.
module Workflow::Edit::Wording
  extend ActiveSupport::Concern

  KEY_STEP_NAME = "step_name".freeze
  KEY_FROM_NAME = "from_name".freeze
  KEY_TO_NAME = "to_name".freeze

  class_methods do
    # check_logs reads as Check logs.
    def title_of(name) = name.to_s.tr("_", " ").squish.upcase_first.presence || "A step"

    # The payload with the names of the steps it touches as they are now, so the edit still names them later.
    def named(operation, payload, steps_by_id)
      payload = payload.to_h.deep_stringify_keys
      name = ->(id) { steps_by_id[id]&.dig("name") }
      case operation
      when Workflow::Edit::OPERATION_CONNECT, Workflow::Edit::OPERATION_DISCONNECT
        payload.merge(KEY_FROM_NAME => name.call(payload["from"]), KEY_TO_NAME => name.call(payload["to"])).compact
      when Workflow::Edit::OPERATION_ADD_STEP then payload
      else payload["step_id"].present? ? payload.merge(KEY_STEP_NAME => name.call(payload["step_id"])).compact : payload
      end
    end
  end

  def author_name = by_halon? ? "Halon" : (author&.actor_display_name || "Someone")

  def step_title = self.class.title_of(payload[KEY_STEP_NAME] || payload.dig("step", "name") || payload["step_id"])

  # What happened, as a toast says it.
  def notice
    case operation
    when Workflow::Edit::OPERATION_ADD_STEP then "#{step_title} was added."
    when Workflow::Edit::OPERATION_REMOVE_STEP then "#{step_title} was removed."
    when Workflow::Edit::OPERATION_MOVE_STEP then "#{step_title} was moved."
    when Workflow::Edit::OPERATION_CONNECT then "#{from_title} now leads to #{to_title}#{route_words}."
    when Workflow::Edit::OPERATION_DISCONNECT then "#{from_title} no longer leads to #{to_title}#{route_words}."
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then payload["step_id"].present? ? "#{step_title} was updated." : "The workflow's outputs were updated."
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then "The trigger was updated."
    when Workflow::Edit::OPERATION_RENAME then renamed_words
    end
  end

  # What happened and who did it, as a version's history lists it.
  def sentence
    what = case operation
    when Workflow::Edit::OPERATION_ADD_STEP then "added #{step_title}"
    when Workflow::Edit::OPERATION_REMOVE_STEP then "removed #{step_title}"
    when Workflow::Edit::OPERATION_MOVE_STEP then "moved #{step_title}"
    when Workflow::Edit::OPERATION_CONNECT then "connected #{from_title} to #{to_title}#{route_words}"
    when Workflow::Edit::OPERATION_DISCONNECT then "disconnected #{from_title} from #{to_title}#{route_words}"
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then payload["step_id"].present? ? "changed #{step_title}" : "changed the workflow's outputs"
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then "changed the trigger"
    when Workflow::Edit::OPERATION_RENAME
      payload["step_id"].present? ? "renamed #{step_title} to #{self.class.title_of(payload['name'])}" : "renamed the workflow to #{payload['name']}"
    end
    "#{author_name} #{what}."
  end

  # A suggestion as the canvas offers it, without who made it, since every suggestion is Halon's.
  def suggestion_words
    case operation
    when Workflow::Edit::OPERATION_ADD_STEP then "Add #{step_title}"
    when Workflow::Edit::OPERATION_REMOVE_STEP then "Remove #{step_title}"
    when Workflow::Edit::OPERATION_MOVE_STEP then "Move #{step_title}"
    when Workflow::Edit::OPERATION_CONNECT then "Connect #{from_title} to #{to_title}#{route_words}"
    when Workflow::Edit::OPERATION_DISCONNECT then "Disconnect #{from_title} from #{to_title}#{route_words}"
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then payload["step_id"].present? ? "Change #{step_title}" : "Change the workflow's outputs"
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then "Change the trigger"
    when Workflow::Edit::OPERATION_RENAME
      payload["step_id"].present? ? "Rename #{step_title} to #{self.class.title_of(payload['name'])}" : "Rename the workflow to #{payload['name']}"
    end
  end

  private

  def from_title = self.class.title_of(payload[KEY_FROM_NAME] || payload["from"])

  def to_title = self.class.title_of(payload[KEY_TO_NAME] || payload["to"])

  def route_words = payload["route"].present? ? " on #{payload['route'].tr('_', ' ')}" : ""

  def renamed_words
    return "#{step_title} was renamed to #{self.class.title_of(payload['name'])}." if payload["step_id"].present?

    "The workflow was renamed to #{payload['name']}."
  end
end
