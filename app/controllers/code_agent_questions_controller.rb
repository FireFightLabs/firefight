# The person a code change runs as answers its coding agent's question from the chat or the fix it was asked in, and can
# change a settled answer while the change is still written.
class CodeAgentQuestionsController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[answer change]

  def answer
    answered = CodeAgentQuestionService.answer_by_id!(current_workspace, params[:id], params[:answer], by: current_membership, option: option)
    redirect_back_or_to agent_chats_path, (answered.ok ? :notice : :alert) => answered.words
  end

  def change
    changed = CodeAgentQuestionService.change_by_id!(current_workspace, params[:id], params[:answer], by: current_membership, option: option)
    redirect_back_or_to agent_chats_path, (changed.ok ? :notice : :alert) => changed.words
  end

  private

  def option = (Integer(params[:option], exception: false) if params[:option].present?)
end
