# How a coding agent asks the person it writes a change for. The question is shown under the change's step in the chat
# or the fix, and in its Slack thread, Halon answers when what it read settles it, and otherwise the person does. A call
# waits a little for the answer and says to wait again, since one request held for minutes would outlive the agent's.
module CodeAgent::QuestionTools
  ASK = "ask_question".freeze
  WAIT = "wait_for_answer".freeze
  # How long one call waits for an answer before it says to call again, under the time an MCP client gives a call.
  WAIT_IN_CALL = 25
  POLL_EVERY = 1
  STILL_WAITING = "No answer yet. Call #{WAIT} to keep waiting, and do nothing else until it answers.".freeze

  # Offered only where the change was asked for, a chat or a fix, since that is where the question can be seen.
  def self.for(session)
    return [] unless session.place

    [
      ::MCP::Tool.define(
        name: ASK,
        description: "Ask the person this change is for one question, when the brief and what you can read leave a choice only " \
                     "they can make, such as which of two behaviours they want. Never ask what reading the repository or the " \
                     "tools would tell you. The answer comes back here, and nobody answering within " \
                     "#{CodeAgentQuestion::ANSWER_WITHIN.in_minutes.to_i} minutes ends the change. At most " \
                     "#{CodeAgentQuestion::MAX_PER_CHANGE} questions per change.",
        input_schema: { type: "object", required: [ "question" ], properties: { question: { type: "string" } } }
      ) do |question:, **|
        asked = CodeAgentQuestion.ask!(session, question)
        CodeAgentQuestionJob.perform_later(asked.id)
        CodeAgent::QuestionTools.answer(asked)
      rescue CodeAgentQuestion::Refused => error
        CodeAgent::QuestionTools.refusal(error.message)
      end,
      ::MCP::Tool.define(
        name: WAIT,
        description: "Keep waiting for the answer to the question you asked.",
        input_schema: { type: "object", properties: {} }
      ) do |**|
        asked = session.questions.last
        asked ? CodeAgent::QuestionTools.answer(asked) : CodeAgent::QuestionTools.refusal("You have not asked a question.")
      end
    ]
  end

  # The answer once there is one, or the question's end once it is overdue, or a word to wait again.
  def self.answer(asked)
    deadline = clock + WAIT_IN_CALL
    loop do
      asked.reload
      asked.expire_if_overdue!
      return text(asked.agent_words) unless asked.open?
      return text(STILL_WAITING) if clock >= deadline

      pause(POLL_EVERY)
    end
  end

  def self.pause(seconds) = sleep(seconds)

  def self.clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def self.text(words) = ::MCP::Tool::Response.new([ { type: "text", text: words } ])

  def self.refusal(words) = ::MCP::Tool::Response.new([ { type: "text", text: words } ], error: true)
end
