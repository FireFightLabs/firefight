# Answers a workflow's Ask a person question, or marks a Manual step's task done, from the run's page. Anyone it asked
# may, and in a test run the person testing too, which the model decides, and a refusal says why in its words.
class WorkflowQuestionsController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: :answer

  def answer
    question = Workflow::Run::Question.where(workspace: current_workspace, run_step_id: run.steps.select(:id)).find(params[:question_id])
    values = params.fetch(:values, {}).permit(*question.fields.map { |field| field[Workflow::Run::Question::FIELD_NAME] }).to_h
    answered = WorkflowQuestionService.answer!(question, by: current_membership, choice: params[:choice].presence, values: values)
    done = question.task? ? "You marked #{workflow.name}'s task done." : "Your answer to #{workflow.name} was sent."
    flash = answered.ok ? { notice: done } : { alert: answered.words }
    redirect_to workflow_path(workflow, WorkflowCanvasController::RUN_QUERY_PARAM => run.id), **flash
  end

  private

  def run = @run ||= workflow.runs.find(params[:run_id])
end
