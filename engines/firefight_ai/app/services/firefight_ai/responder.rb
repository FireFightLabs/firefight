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

    # What the context sent after the chat on every call opens with, since it rides where the person's words do.
    CONTEXT_HEADING = "How things stand as of now, from Firefight rather than from the person:".freeze

    # model is a ModelChoice for a chat told to use one, such as a bench replay comparing models. nil means the workspace's.
    # specialists says the chat hands reads of connected systems to specialists, which its prompt then says.
    def initialize(workspace, inferable:, member: nil, output_style: nil, model: nil, specialists: false)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @output_style = output_style
      @ai_model = model
      @specialists = specialists
    end

    # The app has already saved the question as the last message. stable_context holds for the whole chat and joins the
    # instructions. context can change between turns, so it is sent after the chat on every model call and never saved
    # (AgentLoop), which keeps the instructions and the cached history in front of it the same from turn to turn.
    # deferred_tools are found by the provider's own tool search where it has one (FirefightAi.ready_chat). A reply whose
    # tool call could not be read is asked for once more, and a second one fails the turn as UnreadableReply.
    # purse, on_backup, on_take_over and on_progress go to the loop, see AgentLoop. checks are the app's own checks on a
    # reply that would end the turn, such as the theory board and the challenger, to which the line saying the next step
    # is added when the deployment finishes reads (Configuration#finish_reads).
    def run(chat:, tools:, context:, budget:, stable_context: nil, deferred_tools: [], canceled: -> { false }, on_step: nil, on_chunk: nil,
            nudge: nil, memory: nil, take_messages: nil, purse: nil, on_backup: nil, on_take_over: nil, on_progress: nil, checks: [], &on_turn)
      FirefightAi.translating_errors do
        # A chat grows with every question and each turn resends all of it, so the provider is asked to cache it.
        FirefightAi.ready_chat(chat, choice: ai_model, instructions: [ template_text, stable_context ].compact_blank.join("\n"), tools: tools, deferred_tools: deferred_tools)

        AgentLoop.new(
          chat: chat, budget: budget, answered: -> { false }, canceled: canceled,
          context: ("#{CONTEXT_HEADING}\n#{context}" if context.present?),
          on_step: on_step, on_chunk: on_chunk, nudge: nudge, memory: memory, inference: inference_context, reply_is_answer: true,
          take_messages: take_messages, output: output_cap, choice: ai_model, purpose: AiPurpose::INVESTIGATION,
          purse: purse, on_backup: on_backup, on_take_over: on_take_over, on_progress: on_progress, steady: true,
          checks: (FirefightAi.configuration.finish_reads ? [ NextStep.check ] : []) + checks, retry_malformed: true,
          hold_history: true
        ).run(&on_turn)
      end
    rescue RubyLLM::ToolCallParseError => e
      raise UnreadableReply.new(e.message, reason: e.class.name.demodulize)
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    # The wording as this responder sends it, which names the version of Halon a bench run tested. The heading the
    # context opens with is wording too, though it rides after the chat.
    def prompt_version = Manual.version(worded)

    private

    def output_cap = FirefightAi.output_cap(AiPurpose::INVESTIGATION, choice: ai_model)

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: ai_model.provider_name,
        model: ai_model.model, inferable: @inferable, member: @member,
        prompt_template: FEATURE, prompt_version: prompt_version, prompt_text: Manual.recorded(worded)
      }
    end

    # A reply that only offers a read is sent back when the deployment finishes reads, and only then is Halon told the line.
    def answering = FirefightAi.configuration.finish_reads ? "#{ANSWERING}\n- #{NextStep::RULE}" : ANSWERING

    def worded = "#{template_text}\n#{CONTEXT_HEADING}"

    # The wording, without the per run context.
    def template_text
      <<~PROMPT
        #{ROLE}

        #{Manual::THINKING}

        #{Manual::PEOPLE}

        #{Manual::DONE}

        #{@specialists ? Manual::TOOLS_WITH_SPECIALISTS : Manual::TOOLS}

        #{Manual::PLAYBOOKS}

        #{answering}

        #{Manual::WRITING}
        #{@output_style}
      PROMPT
    end
  end
end
