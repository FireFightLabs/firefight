# The edits that turn one version's content into another, each one of the operations a person makes, so going back is
# history that says who did it rather than a rewrite. Steps are matched by their stable id at each level, the top and
# the inside of every for each. Connections that go come first and connections that arrive last, so no edit names a
# step that is not there.
module Workflow::Edit::Diff
  module_function

  STEP_SETTINGS = Workflow::Edit::Operations::STEP_SETTINGS
  BODY_KEYS = DefinedWorkflow::BODY_KEYS

  # [[operation, payload], ...] that turn from into to.
  def operations(from, to)
    from = from.to_h.deep_stringify_keys
    to = to.to_h.deep_stringify_keys
    found = Hash.new { |hash, key| hash[key] = [] }
    level(from, to, nil, found)
    found[:trigger] << [ Workflow::Edit::OPERATION_CHANGE_TRIGGER, { "trigger" => to["trigger"] } ] if from["trigger"] != to["trigger"]
    if from["outputs"].to_h != to["outputs"].to_h
      found[:settings] << [ Workflow::Edit::OPERATION_CHANGE_CONFIG, { "changes" => { "outputs" => to["outputs"].to_h } } ]
    end
    %i[disconnect remove add rename settings move connect trigger].flat_map { |key| found[key] }
  end

  def level(from, to, within, found)
    before = Array(from["steps"]).index_by { |step| step["id"] }
    after = Array(to["steps"]).index_by { |step| step["id"] }
    place = within ? { "within" => within } : {}

    (edges(from) - edges(to)).each { |edge| found[:disconnect] << [ Workflow::Edit::OPERATION_DISCONNECT, edge.merge(place) ] }
    (before.keys - after.keys).each { |id| found[:remove] << [ Workflow::Edit::OPERATION_REMOVE_STEP, { "step_id" => id } ] }
    (after.keys - before.keys).each { |id| found[:add] << [ Workflow::Edit::OPERATION_ADD_STEP, place.merge("step" => after[id]) ] }
    (before.keys & after.keys).each { |id| step(before[id], after[id], found) }
    (edges(to) - edges(from)).each { |edge| found[:connect] << [ Workflow::Edit::OPERATION_CONNECT, edge.merge(place) ] }
  end

  def step(was, now, found)
    id = now["id"]
    found[:rename] << [ Workflow::Edit::OPERATION_RENAME, { "step_id" => id, "name" => now["name"] } ] if was["name"] != now["name"]
    loop_step = now["kind"] == DefinedWorkflow::KIND_FOR_EACH
    changes = settings_changes(was, now, loop_step)
    found[:settings] << [ Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => id, "changes" => changes } ] if changes.any?
    found[:move] << [ Workflow::Edit::OPERATION_MOVE_STEP, { "step_id" => id, "position" => now["position"] } ] if now["position"] && was["position"] != now["position"]
    level(was["config"].to_h, now["config"].to_h, id, found) if loop_step
  end

  # A config changes by merging, so a key that went is sent as nil. The inside of a for each changes by its own edits.
  def settings_changes(was, now, loop_step)
    changes = {}
    was_config = was["config"].to_h
    now_config = now["config"].to_h
    was_config, now_config = [ was_config, now_config ].map { |config| config.except(*BODY_KEYS) } if loop_step
    if was_config != now_config
      changes["config"] = now_config.merge((was_config.keys - now_config.keys).index_with { nil })
    end
    (STEP_SETTINGS - [ "config" ]).each { |key| changes[key] = now[key] if was[key] != now[key] }
    changes
  end

  def edges(level)
    Array(level["edges"]).map { |edge| { "from" => edge["from"], "to" => edge["to"], "route" => edge["route"].presence }.compact }
  end
end
