# Runs Halon for one step of a workflow run, Ask Halon or Run a skill, on the investigations worker, and hands the step
# its answer. A model that cannot answer hands the step why, so the run says it rather than waiting out its time.
class WorkflowHalonStepJob < ApplicationJob
  queue_as :investigations

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.deliver_failure("Halon could not answer, #{error.reason || 'the model was not reachable'}.")
  end

  def perform(run_id, record_id, engine_step_id, kind, config)
    @engine_step_id = engine_step_id
    run = Workflow::Run.find_by(id: run_id)
    return unless run

    record = Workflow::Run::Step.find_by(id: record_id)
    answer = answer_for(Workflow::HalonStep.new(run, record), kind, config.to_h)
    DefinedWorkflow.deliver!(engine_step_id, DefinedWorkflow::Steps::AskHalon::HANDED_OFF, answer)
  rescue FirefightAi::TerminalError => error
    deliver_failure(error.is_a?(FirefightAi::OutOfCredit) ? error.message : "Halon could not answer, #{error.reason || error.message}.")
  end

  def deliver_failure(words)
    DefinedWorkflow.deliver!(@engine_step_id || arguments[2], DefinedWorkflow::Steps::AskHalon::HANDED_OFF, { Workflow::HalonStep::KEY_ERROR => words })
  end

  private

  def answer_for(halon, kind, config)
    if kind == DefinedWorkflow::Steps::RunSkill.kind
      return halon.follow!(skill_name: config[DefinedWorkflow::Steps::RunSkill::KEY_SKILL], focus: config[DefinedWorkflow::Steps::RunSkill::KEY_FOCUS])
    end

    halon.ask!(question: config[DefinedWorkflow::Steps::AskHalon::KEY_QUESTION], data: config[DefinedWorkflow::Steps::AskHalon::KEY_DATA],
               fields: DefinedWorkflow::Steps::AskHalon.fields_of(config))
  end
end
