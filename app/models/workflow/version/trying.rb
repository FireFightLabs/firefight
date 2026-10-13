# What a test run of a version runs: the whole of it, or a step and the steps before it, so one step is tried without
# what comes after. A step inside a for each is tried with its for each, since the loop is what gives it its item.
module Workflow::Version::Trying
  extend ActiveSupport::Concern

  # The content up to and including the step: the steps it waits on, near or far, and itself. The step no longer takes an
  # error route that leads nowhere, and the outputs, which may name a step left out, are dropped.
  def snapshot_up_to(step_id)
    top_id = top_level_id(step_id) || raise(Workflow::Edit::Refused, "That step is no longer in the workflow.")
    kept = ancestors_of(top_id) + [ top_id ]
    content = snapshot
    content["steps"] = content["steps"].select { |step| kept.include?(step["id"]) }.map do |step|
      step["id"] == top_id && step["on_failure"] == DefinedWorkflow::ON_FAILURE_ERROR_ROUTE ? step.except("on_failure") : step
    end
    content["edges"] = content["edges"].select { |edge| kept.include?(edge["from"]) && kept.include?(edge["to"]) }
    content["outputs"] = {}
    content
  end

  # Every top level step a run reaches before this one, by id.
  def ancestors_of(step_id, found = Set.new)
    Array(edges).each do |edge|
      next unless edge["to"] == step_id && found.exclude?(edge["from"])

      found << edge["from"]
      ancestors_of(edge["from"], found)
    end
    found.to_a
  end

  # Every top level step that runs after this one, by id, which a run started again from it runs again.
  def descendants_of(step_id, found = Set.new)
    Array(edges).each do |edge|
      next unless edge["from"] == step_id && found.exclude?(edge["to"])

      found << edge["to"]
      descendants_of(edge["to"], found)
    end
    found.to_a
  end

  # The top level step a step is, or sits inside.
  def top_level_id(step_id)
    Array(steps).each do |step|
      return step["id"] if step["id"] == step_id
      return step["id"] if Workflow::Version.all_steps(step.dig("config", "steps")).any? { |inner| inner["id"] == step_id }
    end
    nil
  end
end
