module FirefightAi
  # The agent answering a person. Same loop as an investigation, and the reply is the answer. It does the work itself.
  class Responder
    FEATURE = "conversation".freeze

    ROLE = "You are Halon, the SRE on this team. You work for the people of this workspace and act like the best SRE " \
           "they could hire: calm, curious, careful with production and fast to help. In this chat you work for the " \
           "person talking to you, with exactly the permissions they have, so anything they can do in Firefight you can " \
           "do for them: open and update incidents, invite people, manage runbooks and settings, and for an admin, " \
           "permissions. Do it rather than explaining how. You read the systems this workspace connected, follow work " \
           "over time with plans and watches, and propose or make changes within what the workspace allows.".freeze

    # The two facts only a chat has: the reply is the answer, and a cancelled card comes back in the library's words.
    ANSWERING = <<~TEXT.strip.freeze
      How you answer:
      - Your reply is what the person reads, and it ends your turn.
      - A result saying the user denied a call means the person cancelled it on its card, so it was not done because they chose not to.
    TEXT

    # model is a ModelChoice for a chat told to use one, such as a bench replay comparing models. nil means the workspace's.
    def initialize(workspace, inferable:, member: nil, output_style: nil, model: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @output_style = output_style
      @ai_model = model
    end

    # The app has already saved the question as the last message. deferred_tools are found by the provider's own tool
    # search where it has one (FirefightAi.ready_chat).
    # purse, on_backup, on_take_over and on_progress go to the loop, see AgentLoop.
    def run(chat:, tools:, context:, budget:, deferred_tools: [], canceled: -> { false }, on_step: nil, on_chunk: nil,
            nudge: nil, memory: nil, take_messages: nil, purse: nil, on_backup: nil, on_take_over: nil, on_progress: nil, &on_turn)
      FirefightAi.translating_errors do
        # A chat grows with every question and each turn resends all of it, so the provider is asked to cache it.
        FirefightAi.ready_chat(chat, choice: ai_model, instructions: "#{template_text}\n#{context}", tools: tools, deferred_tools: deferred_tools)

        AgentLoop.new(
          chat: chat, budget: budget, answered: -> { false }, canceled: canceled,
          on_step: on_step, on_chunk: on_chunk, nudge: nudge, memory: memory, inference: inference_context, reply_is_answer: true,
          take_messages: take_messages, output: output_cap, choice: ai_model, purpose: AiPurpose::INVESTIGATION,
          purse: purse, on_backup: on_backup, on_take_over: on_take_over, on_progress: on_progress
        ).run(&on_turn)
      end
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    # The wording as this responder sends it, which names the version of Halon a bench run tested.
    def prompt_version = Manual.version(template_text)

    private

    def output_cap = FirefightAi.output_cap(AiPurpose::INVESTIGATION, choice: ai_model)

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: ai_model.provider_name,
        model: ai_model.model, inferable: @inferable, member: @member,
        prompt_template: FEATURE, prompt_version: prompt_version, prompt_text: Manual.recorded(template_text)
      }
    end

    # The wording, without the per run context, which is what the version is taken from.
    def template_text
      <<~PROMPT
        #{ROLE}

        #{Manual::THINKING}

        #{Manual::PEOPLE}

        #{Manual::DONE}

        #{FirefightAi.configuration.specialists ? Manual::TOOLS_WITH_SPECIALISTS : Manual::TOOLS}

        #{Manual::PLAYBOOKS}

        #{ANSWERING}

        #{Manual::WRITING}
        #{@output_style}
      PROMPT
    end
  end
end
