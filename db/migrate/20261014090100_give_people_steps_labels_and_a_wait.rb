# Each Ask a person choice becomes a label with the key its route was already named by, so edges keep working, and
# Ask a person and Approval steps say how long they wait in their own settings, taken from the time limit they had, or
# a day. A step inside a for each is changed the same way.
class GivePeopleStepsLabelsAndAWait < ActiveRecord::Migration[8.1]
  class Version < ActiveRecord::Base
    self.table_name = "workflow_versions"
  end

  WAITING_KINDS = %w[ask_person approval].freeze
  DEFAULT_MINUTES = 1_440
  FEWEST_MINUTES = 5
  MOST_MINUTES = 10_080

  def up
    Version.where("steps::text LIKE ? OR steps::text LIKE ?", "%ask_person%", "%approval%").find_each do |version|
      changed = steps_of(version.steps)
      version.update_columns(steps: changed) unless changed == version.steps
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def steps_of(steps)
    Array(steps).map do |step|
      next step unless step.is_a?(Hash)

      step = step.deep_dup
      config = step["config"].is_a?(Hash) ? step["config"] : {}
      config["steps"] = steps_of(config["steps"]) if step["kind"] == "for_each" && config["steps"].is_a?(Array)
      if WAITING_KINDS.include?(step["kind"])
        config["wait_minutes"] ||= minutes(step.delete("timeout_seconds"))
        config["choices"] = labelled(config["choices"]) if step["kind"] == "ask_person"
      end
      step.merge("config" => config)
    end
  end

  def minutes(seconds)
    return DEFAULT_MINUTES unless seconds.is_a?(Integer) && seconds.positive?

    (seconds / 60.0).ceil.clamp(FEWEST_MINUTES, MOST_MINUTES)
  end

  def labelled(choices)
    Array(choices).map do |choice|
      next choice if choice.is_a?(Hash)

      { "key" => choice.to_s, "label" => choice.to_s.tr("_", " ").upcase_first }
    end
  end
end
