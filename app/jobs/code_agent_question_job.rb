# Shows a coding agent's question where its change was asked for and gives Halon the first try at it, or redraws it
# once it settled another way, outside the agent's own request. Not on the conversations queue, whose workers can all be
# held by the very chats waiting on these answers.
class CodeAgentQuestionJob < ApplicationJob
  queue_as :default

  ASKED = "asked".freeze
  SETTLED = "settled".freeze

  def perform(question_id, moment = ASKED)
    question = CodeAgentQuestion.find_by(id: question_id)
    return unless question

    moment == ASKED ? CodeAgentQuestionService.asked!(question) : CodeAgentQuestionService.redraw!(question)
  end
end
