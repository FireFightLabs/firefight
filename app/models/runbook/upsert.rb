# Steps and conditions are only touched when sent, so changing a summary
# does not silently clear the procedure.
class Runbook::Upsert
  def initialize(workspace)
    @workspace = workspace
  end

  def call(existing, args)
    runbook = existing

    Runbook.transaction do
      if runbook
        runbook.update!(runbook_attributes(args))
      else
        runbook = @workspace.runbooks.create!(name: args[:name].to_s, **runbook_attributes(args))
      end

      runbook.sync_steps!(step_params(args)) if args.key?(:steps)
      runbook.sync_conditions!(condition_params(args)) if args.key?(:conditions)
    end

    runbook
  end

  private

  # inputs, aliases and watch are what makes a runbook one Halon can run, and each is touched only when sent.
  def runbook_attributes(args)
    { name: args[:name], summary: args[:summary], content: args[:content],
      external_url: args[:external_url] }.compact.merge(args.to_h.symbolize_keys.slice(:inputs, :aliases, :watch))
  end

  def step_params(args)
    Array(args[:steps]).map do |step|
      step = step.to_h.with_indifferent_access
      { title: step[:title], instruction: step[:instruction], **step.slice(:tool, :arguments).symbolize_keys }
    end
  end

  def condition_params(args)
    Array(args[:conditions]).map do |condition|
      IncidentCondition::Values.attributes(@workspace, condition.to_h.with_indifferent_access)
    end
  end
end
