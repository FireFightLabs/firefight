# An edit as a person reads it beside the Accept and Dismiss of a suggestion, such as "Set focus on scan to shop.",
# naming the step by the name it has in the version shown.
module Workflow::Edit::Described
  VALUE_LIMIT = 120

  module_function

  def sentence(edit, version)
    payload = edit.payload.to_h
    step = named(version, payload["step_id"])
    case edit.operation
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then config_sentence(payload, step)
    when Workflow::Edit::OPERATION_ADD_STEP then "Add a step called #{payload.dig('step', 'name')}."
    when Workflow::Edit::OPERATION_REMOVE_STEP then "Remove #{step}."
    when Workflow::Edit::OPERATION_RENAME then step ? "Rename #{step} to #{payload['name']}." : "Rename the workflow to #{payload['name']}."
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then "Start it #{Workflow::Trigger.words(payload['trigger']).downcase_first}."
    when Workflow::Edit::OPERATION_CONNECT then "Run #{named(version, payload['to'])} after #{named(version, payload['from'])}."
    when Workflow::Edit::OPERATION_DISCONNECT then "Stop running #{named(version, payload['to'])} after #{named(version, payload['from'])}."
    else "Move #{step}."
    end
  end

  def config_sentence(payload, step)
    changes = payload["changes"].to_h
    settings = changes["config"].to_h.map { |key, value| "#{key.humanize(capitalize: false)} to #{shown(value)}" }
    settings += changes.except("config").map { |key, value| "#{key.humanize(capitalize: false)} to #{shown(value)}" }
    "Set #{settings.to_sentence} on #{step || 'the workflow'}."
  end

  def named(version, id)
    return if id.blank?

    version&.steps_by_id&.dig(id, "name") || "a step that is gone"
  end

  def shown(value) = (value.is_a?(String) ? value : value.to_json).truncate(VALUE_LIMIT)
end
