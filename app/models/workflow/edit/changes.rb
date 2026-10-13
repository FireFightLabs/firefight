# What an edit changes in a version's content, field by field, so a suggestion of Halon's shows the old value struck
# through beside the new one. Values are written as a person reads them, a word as it is and anything else as JSON.
module Workflow::Edit::Changes
  extend ActiveSupport::Concern

  Change = Data.define(:field, :before, :after)

  SETTING_FIELDS = { "timeout_seconds" => "Time limit in seconds", "retry" => "Retries", "on_failure" => "When it fails" }.freeze

  def changes_against(document)
    steps = Workflow::Version.all_steps(document.to_h["steps"]).index_by { |step| step["id"] }
    case operation
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then config_changes(steps[payload["step_id"]], document)
    when Workflow::Edit::OPERATION_RENAME then rename_changes(steps[payload["step_id"]])
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then hash_changes(document.to_h["trigger"].to_h, payload["trigger"].to_h, prefix: "Trigger ")
    else []
    end
  end

  private

  def config_changes(step, document)
    given = payload["changes"].to_h
    return hash_changes(document.to_h["outputs"].to_h, given["outputs"].to_h, prefix: "Output ", merge: false) if payload["step_id"].blank?
    return [] unless step

    found = hash_changes(step["config"].to_h, given["config"].to_h)
    SETTING_FIELDS.each do |key, field|
      next unless given.key?(key)

      found << Change.new(field: field, before: written(step[key]), after: written(given[key])) unless step[key] == given[key]
    end
    found
  end

  def rename_changes(step)
    old = step&.dig("name")
    [ Change.new(field: "Name", before: written(old), after: written(payload["name"])) ]
  end

  def hash_changes(before, after, prefix: "", merge: true)
    keys = merge ? after.keys : (before.keys | after.keys)
    keys.filter_map do |key|
      next if before[key] == after[key]

      Change.new(field: "#{prefix}#{key.to_s.tr('_', ' ')}".upcase_first, before: written(before[key]), after: written(after[key]))
    end
  end

  def written(value)
    return nil if value.nil?

    value.is_a?(String) ? value : value.to_json
  end
end
