# A step reads the run's data through references, the {{...}} syntax runbooks use: {{inputs.region}},
# {{trigger.incident.severity}}, {{steps.check_logs.verdict}}, and inside a for each {{item}} and {{index}}. A step may
# only read a step that runs before it, so a reference never points at data that cannot be there.
module Workflow::Version::References
  extend ActiveSupport::Concern

  REFERENCE = /\{\{\s*([a-z][a-z0-9_]*(?:\.[A-Za-z0-9_-]+)*)\s*\}\}/
  ROOT_INPUTS = DefinedWorkflow::SCOPE_INPUTS
  ROOT_TRIGGER = DefinedWorkflow::SCOPE_TRIGGER
  ROOT_STEPS = DefinedWorkflow::SCOPE_STEPS
  ROOT_ITEM = DefinedWorkflow::SCOPE_ITEM
  ROOT_INDEX = DefinedWorkflow::SCOPE_INDEX
  LOOP_ROOTS = [ ROOT_ITEM, ROOT_INDEX ].freeze

  class_methods do
    # The value with each reference put in its place from the run's scope. A reference that is the whole value keeps
    # the type of what it names, and one naming nothing reads as empty.
    def filled(value, scope) = Placeholders.fill(value, REFERENCE) { |path| dig_path(scope, path) }

    def references_in(value) = Placeholders.references_in(value, REFERENCE)

    def dig_path(scope, path)
      path.split(".").reduce(scope) do |found, key|
        case found
        when Hash then found[key]
        when Array then key.match?(/\A\d+\z/) ? found[key.to_i] : nil
        end
      end
    end
  end

  private

  def reference_problems
    found = level_problems(steps, edges, before: [], in_loop: false)
    self.class.references_in(outputs).each do |path|
      found << output_problem(path, Workflow::Version.all_steps(steps).map { |step| step["name"] })
    end
    found.compact
  end

  def level_problems(level_steps, level_edges, before:, in_loop:)
    level_steps = Array(level_steps)
    sources = Array(level_edges).group_by { |edge| edge["to"] }.transform_values { |edges| edges.map { |edge| edge["from"] } }
    by_id = level_steps.index_by { |step| step["id"] }

    level_steps.flat_map do |step|
      upstream = before + ancestors(step["id"], sources).filter_map { |id| by_id[id]&.dig("name") }
      config = step["config"].to_h
      readable = step["kind"] == DefinedWorkflow::KIND_FOR_EACH ? config.except(*DefinedWorkflow::BODY_KEYS) : config
      problems = self.class.references_in(readable).map { |path| step_problem(step, path, upstream, in_loop) }
      next problems unless step["kind"] == DefinedWorkflow::KIND_FOR_EACH

      problems + level_problems(config["steps"], config["edges"], before: upstream, in_loop: true)
    end
  end

  def ancestors(id, sources, seen = Set.new)
    Array(sources[id]).each do |source|
      next if seen.include?(source)

      seen << source
      ancestors(source, sources, seen)
    end
    seen.to_a
  end

  def step_problem(step, path, upstream, in_loop)
    root, name = path.split(".")
    label = "#{step['name'].presence || 'A step'} uses {{#{path}}}"
    case root
    when ROOT_INPUTS then "#{label}, which is not one of the trigger's inputs." unless Workflow::Trigger.input_keys(trigger).include?(name)
    when ROOT_TRIGGER then nil
    when ROOT_STEPS then "#{label}, which is not a step that runs before it." unless upstream.include?(name)
    when *LOOP_ROOTS then "#{label}, which only a step inside a for each can read." unless in_loop
    else "#{label}, which is not something a step can read."
    end
  end

  def output_problem(path, names)
    root, name = path.split(".")
    case root
    when ROOT_STEPS then "The outputs use {{#{path}}}, which is not a step in the workflow." unless names.include?(name)
    when ROOT_INPUTS then "The outputs use {{#{path}}}, which is not one of the trigger's inputs." unless Workflow::Trigger.input_keys(trigger).include?(name)
    when ROOT_TRIGGER then nil
    else "The outputs use {{#{path}}}, which is not something a workflow can hand back."
    end
  end
end
