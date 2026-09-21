module FirefightAi
  # The agent answering a person. Same loop as an investigation, and the reply is the answer.
  class Responder
    FEATURE = "conversation".freeze

    def initialize(workspace, inferable:, member: nil, output_style: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @output_style = output_style
    end

    # The app has already saved the question as the last message.
    def run(chat:, tools:, context:, budget:, canceled: -> { false }, on_step: nil, on_chunk: nil, nudge: nil, &on_turn)
      FirefightAi.translating_errors do
        chat.with_instructions("#{template_text}\n#{context}")
        chat.with_tools(*tools)
        # A chat grows with every question and each turn resends all of it, so the provider is asked to cache it.
        chat.with_caching

        AgentLoop.new(
          chat: chat, budget: budget, answered: -> { false }, canceled: canceled,
          on_step: on_step, on_chunk: on_chunk, nudge: nudge, inference: inference_context, reply_is_answer: true
        ).run(&on_turn)
      end
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    private

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: ai_model.provider_name,
        model: ai_model.model, inferable: @inferable, member: @member,
        prompt_template: FEATURE, prompt_version: Prompt.version(template_text), prompt_text: template_text
      }
    end

    # The wording, without the per run context, which is what the version is taken from.
    def template_text
      <<~PROMPT
        You are Firefight, working for the person talking to you. You answer questions and you act in Firefight on their behalf, with exactly the permissions they have. Be brief and exact.

        How to work:
        - You hold almost no tools to begin with. Call find_tools with what you need, such as "recent deploys", "declare an incident" or "grant a permission set", and the ones this person may use become callable.
        - You can do anything this person can do in Firefight: open and update incidents, invite people, assign roles, manage runbooks and settings, and for an admin, manage permissions. Find the tool and use it rather than explaining how to do it by hand.
        - Change something only when the person asked for that change. Say what you changed.
        - Some changes wait for the person to confirm first. When a tool result says the user denied it, they cancelled it themselves, so say it was not done because they cancelled, never that they lack permission.
        - State nothing a tool result or the facts below do not support. Say what you do not know.
        - Never say you cannot check or do something without calling find_tools for it first, including when asked what you are able to do. find_tools also tells you when a tool exists but this person may not use it, or when nothing is connected, and that is worth saying.
        - When a tool refuses, tell the person plainly and who can do it instead.
        - #{Evidence::RULE}
        - When a question needs real work, several tools and a written answer, call start_investigation instead of doing it here.

        How to answer:
        - Reply in plain prose when you have the answer. Your reply is what the person reads, so it ends your turn.
        - A few sentences beats a report. No preamble, no restating the question.
        #{@output_style}
      PROMPT
    end
  end
end
