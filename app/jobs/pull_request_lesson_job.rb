# Reads what a person's handling of a pull request Halon opened teaches, once it merged or closed, apart from whatever
# heard it ended.
class PullRequestLessonJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(session_id)
    PullRequestLessonService.new(CodeAgentSession.find(session_id)).learn!
  end
end
