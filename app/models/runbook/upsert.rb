# Steps and conditions are only touched when sent, so changing a summary
# does not silently clear the procedure.
#
# A step list without a tool step changes only the checklist, so writing back what get_runbook read never clears what
# the linked workflow runs.
class Runbook::Upsert
  RUNNABLE = %i[inputs watch].freeze

  attr_reader :workflow_written

  def initialize(workspace)
    @workspace = workspace
  end

  def call(existing, args, by: nil)
    runbook = existing

    Runbook.transaction do
      if runbook
        runbook.update!(runbook_attributes(args))
      else
        runbook = @workspace.runbooks.create!(name: args[:name].to_s, **runbook_attributes(args))
      end

      runbook.sync_steps!(step_params(args)) if args.key?(:steps)
      runbook.sync_conditions!(condition_params(args)) if args.key?(:conditions)
      @workflow_written = runbook.write_runnable_parts!(runnable_params(args), by: by) if runnable?(args)
    end

    runbook
  end

  def runnable?(args) = Runbook.names_a_run?(args)

  private

  # Aliases are touched only when sent.
  def runbook_attributes(args)
    { name: args[:name], summary: args[:summary], content: args[:content],
      external_url: args[:external_url] }.compact.merge(args.to_h.symbolize_keys.slice(:aliases))
  end

  def step_params(args)
    Array(args[:steps]).map do |step|
      step = step.to_h.with_indifferent_access
      { title: step[:title], instruction: step[:instruction] }
    end
  end

  def tool_steps(args)
    Array(args[:steps]).map { |step| step.to_h.with_indifferent_access }.select { |step| step[:tool].present? }
  end

  def runnable_params(args)
    given = args.to_h.symbolize_keys.slice(*RUNNABLE)
    given[:inputs] = Array(given[:inputs]).map { |input| input.to_h.stringify_keys.slice(*Runbook::Procedure::INPUT_FIELDS).transform_values { |value| value.to_s.strip } } if given.key?(:inputs)
    given[:watch] = given[:watch].presence&.to_h&.deep_stringify_keys if given.key?(:watch)
    steps = tool_steps(args)
    given[:steps] = steps.map { |step| step.slice(*Runbook::WorkflowShape::STEP_FIELDS).to_h.deep_stringify_keys.compact } if steps.any?
    given
  end

  def condition_params(args)
    Array(args[:conditions]).map do |condition|
      IncidentCondition::Values.attributes(@workspace, condition.to_h.with_indifferent_access)
    end
  end
end
