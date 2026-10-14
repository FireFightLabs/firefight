# What each edit does to a version's content, as a plain change from one document to the next. A step is found by its
# id wherever it is, inside a for each too, and a step or connection added inside a for each names it as within.
# Renaming a step rewrites every reference to its old name, so nothing that read it breaks.
module Workflow::Edit::Operations
  module_function

  STEP_SETTINGS = %w[config timeout_seconds retry on_failure].freeze
  ID_LENGTH = 12

  def apply(document, operation, payload)
    document = document.deep_dup
    payload = payload.to_h.deep_stringify_keys
    case operation
    when Workflow::Edit::OPERATION_ADD_STEP then add_step(document, payload)
    when Workflow::Edit::OPERATION_REMOVE_STEP then remove_step(document, payload)
    when Workflow::Edit::OPERATION_MOVE_STEP then change_step(document, payload) { |step| step["position"] = payload["position"].to_h.slice("x", "y") }
    when Workflow::Edit::OPERATION_CONNECT then connect(document, payload)
    when Workflow::Edit::OPERATION_DISCONNECT then disconnect(document, payload)
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then change_config(document, payload)
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then document.merge("trigger" => payload["trigger"].to_h)
    when Workflow::Edit::OPERATION_RENAME then rename(document, payload)
    else raise Workflow::Edit::Refused, "That is not a change a workflow takes."
    end
  end

  # The payload as it is kept, with a new step given its id first, so the edit names the step it added.
  def prepared(operation, payload)
    payload = payload.to_h.deep_stringify_keys
    return payload unless operation == Workflow::Edit::OPERATION_ADD_STEP

    payload.merge("step" => payload["step"].to_h.merge("id" => payload.dig("step", "id").presence || new_step_id))
  end

  # What an edit touches, so an edit made on an older revision is refused when someone changed the same thing since.
  def targets(operation, payload)
    payload = payload.to_h.deep_stringify_keys
    case operation
    when Workflow::Edit::OPERATION_ADD_STEP then [ payload.dig("step", "id") ].compact
    when Workflow::Edit::OPERATION_CONNECT, Workflow::Edit::OPERATION_DISCONNECT then [ edge_target(payload) ]
    when Workflow::Edit::OPERATION_CHANGE_TRIGGER then [ Workflow::Edit::TARGET_TRIGGER ]
    when Workflow::Edit::OPERATION_CHANGE_CONFIG then [ payload["step_id"].presence || Workflow::Edit::TARGET_OUTPUTS ]
    else [ payload["step_id"].presence || Workflow::Edit::TARGET_WORKFLOW ]
    end
  end

  def edge_target(payload) = "edge:#{payload['from']}>#{payload['to']}:#{payload['route']}"

  # A new step gets an id that never changes, which edges, runs and history name it by.
  def new_step_id = "step_#{SecureRandom.alphanumeric(ID_LENGTH).downcase}"

  def add_step(document, payload)
    step = payload["step"].to_h.slice("id", "name", "kind", "config", "position", *STEP_SETTINGS)
    step["id"] = step["id"].presence || new_step_id
    step["config"] = settled(step["kind"], step["config"].to_h)
    raise Workflow::Edit::Refused, "A step needs a name." if step["name"].blank?
    raise Workflow::Edit::Refused, "A step with that id is already in the workflow." if find_step(document, step["id"])
    raise Workflow::Edit::Refused, "A step called #{step['name']} is already in the workflow." if all_steps(document).any? { |other| other["name"] == step["name"] }

    container(document, payload["within"])["steps"] << step
    document
  end

  def remove_step(document, payload)
    id = payload["step_id"]
    level = level_holding(document, id) || raise(Workflow::Edit::Refused, missing_step)
    level["steps"].reject! { |step| step["id"] == id }
    level["edges"].reject! { |edge| edge["from"] == id || edge["to"] == id }
    document
  end

  def change_step(document, payload)
    step = find_step(document, payload["step_id"]) || raise(Workflow::Edit::Refused, missing_step)
    yield step
    document
  end

  def connect(document, payload)
    level = container(document, payload["within"])
    ids = level["steps"].map { |step| step["id"] }
    raise Workflow::Edit::Refused, "Both steps must be in the same part of the workflow." unless ids.include?(payload["from"]) && ids.include?(payload["to"])

    edge = { "from" => payload["from"], "to" => payload["to"], "route" => payload["route"].presence }.compact
    raise Workflow::Edit::Refused, "Those steps are already connected that way." if level["edges"].include?(edge)

    level["edges"] << edge
    document
  end

  def disconnect(document, payload)
    level = container(document, payload["within"])
    edge = { "from" => payload["from"], "to" => payload["to"], "route" => payload["route"].presence }.compact
    raise Workflow::Edit::Refused, "Those steps are not connected that way." unless level["edges"].delete(edge)

    document
  end

  # Changes settings of a step, merging its config so one field changes at a time, or the outputs when no step is named.
  def change_config(document, payload)
    changes = payload["changes"].to_h
    return document.merge("outputs" => changes["outputs"].to_h) if payload["step_id"].blank?

    change_step(document, payload) do |step|
      changes.slice(*STEP_SETTINGS).each do |key, value|
        if key == "config"
          step["config"] = settled(step["kind"], step["config"].to_h.merge(value.to_h).compact)
        elsif value.nil?
          step.delete(key)
        else
          step[key] = value
        end
      end
    end
  end

  # What Firefight derives in a kind's config, such as each choice's key, is filled in as the edit lands.
  def settled(kind, config) = DefinedWorkflow::Steps.for(kind)&.settled_config(config) || config

  def rename(document, payload)
    name = payload["name"].to_s.strip
    raise Workflow::Edit::Refused, "A step needs a name." if name.blank?

    step = find_step(document, payload["step_id"]) || raise(Workflow::Edit::Refused, missing_step)
    raise Workflow::Edit::Refused, "A step called #{name} is already in the workflow." if all_steps(document).any? { |other| other["name"] == name && other["id"] != step["id"] }

    old = step["name"]
    step["name"] = name
    rewrite_references(document, old, name)
  end

  def rewrite_references(value, old, new)
    pattern = /(\{\{\s*steps\.)#{Regexp.escape(old)}(?=[.\s}])/
    case value
    when String then value.gsub(pattern) { "#{Regexp.last_match(1)}#{new}" }
    when Hash then value.transform_values { |inner| rewrite_references(inner, old, new) }
    when Array then value.map { |inner| rewrite_references(inner, old, new) }
    else value
    end
  end

  def all_steps(document) = Workflow::Version.all_steps(document["steps"])

  def find_step(document, id) = id.present? ? all_steps(document).find { |step| step["id"] == id } : nil

  # The top level, or the inside of the for each named within.
  def container(document, within)
    return ensure_lists(document) if within.blank?

    loop_step = find_step(document, within)
    raise Workflow::Edit::Refused, "Only a for each holds steps inside it." unless loop_step && loop_step["kind"] == DefinedWorkflow::KIND_FOR_EACH

    loop_step["config"] = loop_step["config"].to_h
    ensure_lists(loop_step["config"])
  end

  def level_holding(document, id)
    ensure_lists(document)
    return document if document["steps"].any? { |step| step["id"] == id }

    document["steps"].select { |step| step["kind"] == DefinedWorkflow::KIND_FOR_EACH }.each do |loop_step|
      loop_step["config"] = loop_step["config"].to_h
      found = level_holding(loop_step["config"], id)
      return found if found
    end
    nil
  end

  def ensure_lists(level)
    level["steps"] = Array(level["steps"])
    level["edges"] = Array(level["edges"])
    level
  end

  def missing_step = "That step is no longer in the workflow."
end
