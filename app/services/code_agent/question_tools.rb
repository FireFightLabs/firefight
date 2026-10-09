# How a coding agent asks the person it writes a change for. The question is shown under the change's step in the chat
# or the fix, and in its thread, Halon answers when what it read settles it, and otherwise the person does. A call
# waits a little for the answer and says to wait again, since one request held for minutes would outlive the agent's.
module CodeAgent::QuestionTools
  ASK = "ask_question".freeze
  WAIT = "wait_for_answer".freeze
  # How long one call waits for an answer before it says to call again, under the time an MCP client gives a call.
  WAIT_IN_CALL = 25
  POLL_EVERY = 1
  # Seen in a real change, an agent asked about "Slack team T" and "team A", and the person could not tell what it meant.
  PLAIN = "Write it for someone who does not know the code. Use a concrete example with real-sounding names, never " \
          "placeholders such as team T or team A, say what happens today, then ask, and give the options in plain words. " \
          "For example: \"You are in the Acme workspace, which is connected to Acme's Slack. You sign in with Slack from a " \
          "different company's Slack, Side Project, which no workspace uses yet. Today Firefight offers to create a new " \
          "workspace for Side Project. What should happen?\" #{FirefightAi::Copy::PEOPLE} #{FirefightAi::Copy::QUOTING}".freeze
  STILL_WAITING = "No answer yet. Call #{WAIT} to keep waiting, and do nothing else until it answers.".freeze

  # Offered only where the change was asked for, a chat or a fix, since that is where the question can be seen.
  def self.for(session)
    return [] unless session.place

    [
      ::MCP::Tool.define(
        name: ASK,
        description: "Ask the person this change is for one question, when the brief and what you can read leave a choice only " \
                     "they can make, such as which of two behaviours they want. Never ask what reading the repository or the " \
                     "tools would tell you. Before asking, read the code for how the app already behaves in the same situation. " \
                     "Give #{CodeAgentQuestion::MIN_OPTIONS} to #{CodeAgentQuestion::MAX_OPTIONS} options, each with a short label and " \
                     "a one-line consequence, and recommend the option most consistent with the existing behaviour and the person's " \
                     "own words, with a one-sentence reason. The person picks one or writes something else, and the answer comes " \
                     "back here. Nobody answering within #{CodeAgentQuestion::ANSWER_WITHIN.in_minutes.to_i} minutes means your " \
                     "recommendation. At most #{CodeAgentQuestion::MAX_PER_CHANGE} questions per change. #{CodeAgent::QuestionTools::PLAIN}",
        input_schema: {
          type: "object", required: %w[question options recommended reason],
          properties: {
            question: { type: "string", description: "The question, understandable on first read by someone who does not know the code: a concrete " \
                                                     "example with real-sounding names, what Firefight does today, then the question in a short line" },
            options: {
              type: "array", minItems: CodeAgentQuestion::MIN_OPTIONS, maxItems: CodeAgentQuestion::MAX_OPTIONS,
              items: { type: "object", required: %w[label consequence],
                       properties: { label: { type: "string", description: "A few words naming the choice" },
                                     consequence: { type: "string", description: "What choosing it leads to, in one line" } } }
            },
            recommended: { type: "string", description: "The label of the option you recommend, the one most consistent with how the code already behaves and what the person said" },
            reason: { type: "string", description: "Why you recommend it, in one sentence, naming the existing behaviour it follows, or quoting " \
                                                 "the person's words it follows exactly and in quotes" }
          }
        }
      ) do |question:, options: [], recommended: nil, reason: nil, **|
        asked = CodeAgentQuestion.ask!(session, question, options: options, recommended: recommended, reason: reason)
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
