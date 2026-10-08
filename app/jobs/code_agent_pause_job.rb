# Tells where a code change came from that it paused at its spending limit, with Continue and Stop.
class CodeAgentPauseJob < ApplicationJob
  queue_as :default

  def perform(pause_id)
    pause = CodeAgentSession::Pause.find_by(id: pause_id)
    CodeAgentPauseService.tell!(pause) if pause
  end
end
