# The person a code change runs as continues or stops it once it paused at its spending limit, from the step in the chat.
class CodeAgentPausesController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[continue stop]

  def continue
    decide { |pause| CodeAgentPauseService.continue!(pause, by: current_membership) }
  end

  def stop
    decide { |pause| CodeAgentPauseService.stop!(pause, by: current_membership) }
  end

  private

  def decide
    pause = CodeAgentSession::Pause.find_by(id: params[:id], workspace_id: current_workspace.id)
    refusal = pause ? yield(pause) : CodeAgentPauseService::GONE
    redirect_back_or_to agent_chats_path, (refusal ? :alert : :notice) => refusal || CodeAgentPauseService.decided_words(pause)
  end
end
