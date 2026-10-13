# What changed between two versions of a workflow, as sentences a person reads before taking a newer library version:
# steps added, removed or changed (found by their stable ids, inside each for each too), connections added or removed,
# the trigger and the outputs.
module Workflow::Changes
  KIND_ADDED = "added".freeze
  KIND_REMOVED = "removed".freeze
  KIND_CHANGED = "changed".freeze

  Change = Data.define(:kind, :text)

  STEP_FIELDS = { "name" => "its name", "kind" => "what it does", "config" => "its settings", "retry" => "its retries",
                  "timeout_seconds" => "its time limit", "on_failure" => "what happens when it fails" }.freeze

  module_function

  def between(before, after)
    before = before.to_h.stringify_keys
    after = after.to_h.stringify_keys
    old_steps = Workflow::Version.steps_by_id_in(before["steps"])
    new_steps = Workflow::Version.steps_by_id_in(after["steps"])
    names = old_steps.merge(new_steps).transform_values { |step| step["name"] }

    [ *trigger_changes(before["trigger"], after["trigger"]), *step_changes(old_steps, new_steps),
      *edge_changes(before, after, names), *output_changes(before["outputs"], after["outputs"]) ]
  end

  def trigger_changes(before, after)
    return [] if before.to_h == after.to_h

    kind = after.to_h["kind"].to_s.humanize(capitalize: false)
    words = before.to_h["kind"] == after.to_h["kind"] ? "The #{kind} trigger's settings changed." : "It starts on a #{kind} trigger now."
    [ Change.new(kind: KIND_CHANGED, text: words) ]
  end

  def step_changes(old_steps, new_steps)
    added = (new_steps.keys - old_steps.keys).map { |id| Change.new(kind: KIND_ADDED, text: "Added the step #{described(new_steps[id])}.") }
    removed = (old_steps.keys - new_steps.keys).map { |id| Change.new(kind: KIND_REMOVED, text: "Removed the step #{described(old_steps[id])}.") }
    changed = (old_steps.keys & new_steps.keys).filter_map do |id|
      fields = STEP_FIELDS.keys.reject { |field| old_steps[id][field] == new_steps[id][field] }
      next if fields.empty?

      Change.new(kind: KIND_CHANGED, text: "Changed #{fields.map { |field| STEP_FIELDS[field] }.to_sentence} of the step #{new_steps[id]['name']}.")
    end
    added + removed + changed
  end

  def edge_changes(before, after, names)
    old_edges = edges_in(before)
    new_edges = edges_in(after)
    [ *(new_edges - old_edges).map { |edge| Change.new(kind: KIND_ADDED, text: "Connected #{connection(edge, names)}.") },
      *(old_edges - new_edges).map { |edge| Change.new(kind: KIND_REMOVED, text: "Disconnected #{connection(edge, names)}.") } ]
  end

  def output_changes(before, after)
    before = before.to_h
    after = after.to_h
    keys = (before.keys | after.keys).reject { |key| before[key] == after[key] }
    keys.empty? ? [] : [ Change.new(kind: KIND_CHANGED, text: "Changed what it hands back: #{keys.sort.to_sentence}.") ]
  end

  def described(step) = "#{step['name']} (#{step['kind'].to_s.humanize(capitalize: false)})"

  def connection(edge, names)
    from, to, route = edge.values_at("from", "to", "route")
    "#{names[from] || from} to #{names[to] || to}#{" on #{route}" if route.present?}"
  end

  # Every connection, inside each for each too, as from, to and route.
  def edges_in(content)
    top = Array(content["edges"]).map { |edge| edge.to_h.slice("from", "to", "route") }
    inner = Workflow::Version.all_steps(content["steps"]).select { |step| step["kind"] == DefinedWorkflow::KIND_FOR_EACH }
                             .flat_map { |step| Array(step.dig("config", "edges")).map { |edge| edge.to_h.slice("from", "to", "route") } }
    top + inner
  end
end
