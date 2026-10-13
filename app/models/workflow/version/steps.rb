# What a version's steps are, as their kinds say (DefinedWorkflow::Steps): what each must hold to be published, which of
# them change something, and what the workflow's own identity needs granted to run them all. A change carries its undo
# and ends with a check, as a plan's does: some step that reads runs after it, such as reading the resource's status,
# watching it or asking Halon whether it held.
module Workflow::Version::Steps
  extend ActiveSupport::Concern

  # Each step's kind by its id, inside each for each too. nil for a kind nothing defines.
  def step_kinds = Workflow::Version.all_steps(steps).to_h { |step| [ step["id"], DefinedWorkflow::Steps.for(step["kind"]) ] }

  # Every step that changes something outside Firefight and so says how to undo it and is followed by a check.
  def changing_steps
    kinds = step_kinds
    Workflow::Version.all_steps(steps).select { |step| kinds[step["id"]]&.undoable?(step["config"].to_h, workflow.workspace) }
  end

  # Whether any step changes anything, a message included, which a test run pretends unless the tester turns it on.
  def steps_that_change
    kinds = step_kinds
    Workflow::Version.all_steps(steps).select { |step| kinds[step["id"]]&.changes?(step["config"].to_h, workflow.workspace) }
  end

  # What the workflow's own identity needs granted to run every step (DefinedWorkflow::Reach::Needed), once each.
  def reach
    kinds = step_kinds
    Workflow::Version.all_steps(steps).flat_map { |step| kinds[step["id"]]&.reach(step["config"].to_h, workflow.workspace).to_a }.uniq(&:key)
  end

  private

  def step_problems
    kinds = step_kinds
    Workflow::Version.all_steps(steps).flat_map { |step| kinds[step["id"]]&.problems(step, workflow.workspace).to_a }
  end

  def check_problems
    readers = Workflow::Version.all_steps(steps).select { |step| checks?(step) }.map { |step| step["id"] }
    changing_steps.filter_map do |step|
      next if (after(step["id"]) & readers).any?

      "#{step['name'].presence || 'A step'} changes something, so a step that reads how it went needs to run after it."
    end
  end

  def checks?(step)
    DefinedWorkflow::Steps.for(step["kind"])&.checks?(step["config"].to_h, workflow.workspace) || false
  end

  # Every step that runs after this one: along the edges of its own level, and every step inside a for each after it.
  def after(id)
    level = level_of(id) || { steps: [], edges: [] }
    targets = Array(level[:edges]).group_by { |edge| edge["from"] }.transform_values { |edges| edges.map { |edge| edge["to"] } }
    seen = Set.new
    pending = Array(targets[id]).dup
    while (current = pending.shift)
      next if seen.include?(current)

      seen << current
      pending.concat(Array(targets[current]))
    end
    loops = Array(level[:steps]).select { |step| seen.include?(step["id"]) && step["kind"] == DefinedWorkflow::KIND_FOR_EACH }
    seen.to_a + loops.flat_map { |loop| Workflow::Version.all_steps(loop.dig("config", "steps")).map { |each| each["id"] } }
  end

  def level_of(id, level_steps = steps, level_edges = edges)
    return { steps: level_steps, edges: level_edges } if Array(level_steps).any? { |step| step["id"] == id }

    Array(level_steps).each do |step|
      next unless step["kind"] == DefinedWorkflow::KIND_FOR_EACH

      found = level_of(id, step.dig("config", "steps"), step.dig("config", "edges"))
      return found if found
    end
    nil
  end
end
