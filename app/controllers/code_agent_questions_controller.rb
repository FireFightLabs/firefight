# The person a code change runs as answers its coding agent's question from the chat or the fix it was asked in.
class CodeAgentQuestionsController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[answer]

  def answer
    option = Integer(params[:option], exception: false) if params[:option].present?
    answered = CodeAgentQuestionService.answer_by_id!(current_workspace, params[:id], params[:answer], by: current_membership, option: option)
    redirect_back_or_to agent_chats_path, (answered.ok ? :notice : :alert) => answered.words
  end
end
