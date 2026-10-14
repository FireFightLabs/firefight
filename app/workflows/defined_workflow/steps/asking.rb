# What Ask a person and the Manual step share: a Workflow::Run::Question kept on the step's row, sent where it is asked
# by WorkflowQuestionJob, and an answer delivered back to the parked step (DefinedWorkflow.deliver!). A question nobody
# answers within the step's wait is withdrawn and the step takes its route for that, unless an answer won the race.
module DefinedWorkflow::Steps::Asking
  QUESTION = Workflow::Run::Question
  ASKED = "answer".freeze

  def perform
    attributes = QUESTION.exists?(engine_step_id: @step.id) ? {} : question_attributes
    answer = await(ASKED) do |name|
      question = QUESTION.create!(workspace: workspace, run_step: record, engine_step_id: @step.id, delivery_key: name,
                                  due_at: Time.current + handed_off_limit, **attributes)
      WorkflowQuestionJob.perform_later(question.id)
    end
    return answer if answer.is_a?(SolidWorkflow::Park)

    answered(answer)
  rescue SolidWorkflow::TimeLimitReached
    unanswered
  end

  private

  # An answer that won the race with the wait still counts.
  def unanswered
    question = QUESTION.find_by(engine_step_id: @step.id)
    if question&.expire!
      WorkflowQuestionJob.perform_later(question.id)
    elsif question&.answered?
      return answered(question.answer.merge("by" => question.answered_by&.actor_display_name))
    end
    nobody_answered
  end
end
