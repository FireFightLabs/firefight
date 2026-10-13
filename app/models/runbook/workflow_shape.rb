# A runbook's tool steps, inputs and watch as a workflow holds them, and back. Only a chain of call_tool steps with at
# most one watch at the end, and nothing a runbook cannot hold, reads back.
module Runbook::WorkflowShape
  Parts = Data.define(:steps, :inputs, :watch) do
    def initialize(steps: [], inputs: [], watch: nil) = super

    def empty? = steps.empty? && inputs.empty? && watch.blank?
  end

  KIND_CALL_TOOL = DefinedWorkflow::Steps::CallTool.kind
  KIND_WATCH = DefinedWorkflow::Steps::Watch.kind
  KEY_TOOL = DefinedWorkflow::Steps::CallTool::KEY_TOOL
  KEY_ARGUMENTS = DefinedWorkflow::Steps::CallTool::KEY_ARGUMENTS
  KEY_UNDO = DefinedWorkflow::Steps::Base::KEY_UNDO
  STEP_FIELDS = %w[title tool arguments undo].freeze
  STEP_KEYS = %w[id name kind config position].freeze
  TOOL_CONFIG = [ KEY_TOOL, KEY_ARGUMENTS, KEY_UNDO ].freeze
  WATCH_NAME = "watch".freeze
  NAME_LIMIT = 60
  WORKFLOW_INPUT = /\{\{\s*inputs\.([a-z][a-z0-9_]*)\s*\}\}/

  module_function

  # A step keeps its id from before when it keeps its name.
  def content(parts, ids: {})
    names = []
    steps = parts.steps.map do |step|
      name = free_name(step["title"], names)
      config = { KEY_TOOL => step["tool"].to_s, KEY_ARGUMENTS => to_workflow(step["arguments"].to_h) }
      config[KEY_UNDO] = step["undo"].to_s.strip if step["undo"].present?
      { "id" => ids[name] || Workflow::Edit::Operations.new_step_id, "name" => name, "kind" => KIND_CALL_TOOL, "config" => config }
    end
    if parts.watch.present?
      name = free_name(WATCH_NAME, names)
      steps << { "id" => ids[name] || Workflow::Edit::Operations.new_step_id, "name" => name, "kind" => KIND_WATCH, "config" => to_workflow(parts.watch) }
    end
    {
      "trigger" => { Workflow::Trigger::KEY_KIND => Workflow::Trigger::KIND_MANUAL, Workflow::Trigger::KEY_INPUTS => parts.inputs.map { |input| input.slice(*Workflow::Trigger::INPUT_FIELDS) } },
      "steps" => steps,
      "edges" => steps.each_cons(2).map { |from, to| { "from" => from["id"], "to" => to["id"] } },
      "outputs" => {}
    }
  end

  def parts_of(version)
    return Parts.new if version.nil?
    return unless version.trigger.to_h[Workflow::Trigger::KEY_KIND] == Workflow::Trigger::KIND_MANUAL
    return unless version.outputs.blank?

    ordered = in_order(version.steps, version.edges)
    return unless ordered

    watch = ordered.last if ordered.last&.dig("kind") == KIND_WATCH
    tools = watch ? ordered[0...-1] : ordered
    return unless tools.all? { |step| tool_step?(step) }

    steps = tools.map do |step|
      config = step["config"].to_h
      arguments = to_runbook(config[KEY_ARGUMENTS].to_h)
      return nil if arguments.nil?

      { "title" => step["name"], "tool" => config[KEY_TOOL], "arguments" => arguments, "undo" => config[KEY_UNDO].presence }.compact
    end
    watched = watch && to_runbook(watch["config"].to_h)
    return if watch && watched.nil?

    Parts.new(steps: steps, inputs: Workflow::Trigger.inputs(version.trigger).map { |input| input.slice(*Workflow::Trigger::INPUT_FIELDS) }, watch: watched)
  end

  def in_order(steps, edges)
    steps = Array(steps)
    edges = Array(edges)
    return [] if steps.empty? && edges.empty?
    return if steps.any? { |step| (step.keys - STEP_KEYS).any? }
    return if edges.any? { |edge| edge["route"].present? } || edges.size != steps.size - 1

    by_id = steps.index_by { |step| step["id"] }
    targets = edges.to_h { |edge| [ edge["from"], edge["to"] ] }
    first = steps.map { |step| step["id"] } - edges.map { |edge| edge["to"] }
    return unless first.size == 1 && targets.size == edges.size

    ordered = [ by_id[first.first] ]
    ordered << by_id[targets[ordered.last["id"]]] while targets[ordered.last["id"]] && ordered.size <= steps.size
    ordered.compact.size == steps.size ? ordered : nil
  end

  def tool_step?(step)
    step["kind"] == KIND_CALL_TOOL && (step["config"].to_h.keys - TOOL_CONFIG).empty?
  end

  def to_workflow(value) = Placeholders.fill(value, Runbook::Procedure::PLACEHOLDER) { |key| "{{#{Workflow::Version::References::ROOT_INPUTS}.#{key}}}" }

  # nil when the value reads anything but an input.
  def to_runbook(value)
    referenced = Workflow::Version.references_in(value)
    return unless referenced.all? { |path| path.match?(/\A#{Workflow::Version::References::ROOT_INPUTS}\.[a-z][a-z0-9_]*\z/) }

    Placeholders.fill(value, WORKFLOW_INPUT) { |key| "{{#{key}}}" }
  end

  def free_name(title, taken)
    base = title.to_s.parameterize(separator: "_").sub(/\A[^a-z]+/, "").first(NAME_LIMIT).delete_suffix("_").presence || "step"
    name = base
    number = 1
    name = "#{base}_#{number += 1}" while taken.include?(name)
    taken << name
    name
  end
end
