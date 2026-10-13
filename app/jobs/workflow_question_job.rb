# Asks the people a workflow's question names, or redraws where it was asked once it is settled
# (WorkflowQuestionService).
class WorkflowQuestionJob < ApplicationJob
  queue_as :default

  def perform(question_id)
    question = Workflow::Run::Question.find_by(id: question_id)
    WorkflowQuestionService.ask!(question) if question
  end
end
