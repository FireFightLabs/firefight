module FirefightAi
  # The agent answering a person. Same loop as an investigation, and the reply is the answer. It does the work itself.
  class Responder
    FEATURE = "conversation".freeze

    # Asked once before an answer built on what was looked up goes out. The draft is held, so the person reads only what
    # follows. A draft that only repeats what results showed goes out unchanged, so a plain lookup is not run twice.
    CHECK = "Before this answer goes out, look at each claim in it. A claim that only repeats a value a result you read " \
            "shows needs no check. If every claim is like that, write the answer as it is and run nothing. A claim that " \
            "goes further, such as a cause, a diagnosis or a recommendation, needs one. Name the claim and the check that " \
            "would show it false. If you have not run that check and can, run it now. Only a result you read can change " \
            "the answer. Correct a claim a result contradicts, and never replace it with one you reasoned your way to " \
            "without a result that shows it. Say a possibility you could not check is unchecked, or leave it out. Then " \
            "write the answer the person will read, in full, changed or not, as a plain answer that never mentions this " \
            "check. They have not seen your draft.".freeze

    def initialize(workspace, inferable:, member: nil, output_style: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @output_style = output_style
    end

    # The app has already saved the question as the last message.
    # check and hold go to the loop, see AgentLoop.
    def run(chat:, tools:, context:, budget:, canceled: -> { false }, on_step: nil, on_chunk: nil, nudge: nil, memory: nil,
            check: nil, hold: nil, take_messages: nil, &on_turn)
      FirefightAi.translating_errors do
        chat.with_instructions("#{template_text}\n#{context}")
        chat.with_tools(*tools)
        # A chat grows with every question and each turn resends all of it, so the provider is asked to cache it.
        chat.with_caching

        AgentLoop.new(
          chat: chat, budget: budget, answered: -> { false }, canceled: canceled,
          on_step: on_step, on_chunk: on_chunk, nudge: nudge, memory: memory, inference: inference_context, reply_is_answer: true,
          check: check, hold: hold, take_messages: take_messages
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
        - You hold almost no tools to begin with. open_tools lists every group of tools there is. Open the group that fits what you need next, and the tools in it this person may use become callable.
        - You can do anything this person can do in Firefight: open and update incidents, invite people, assign roles, manage runbooks and settings, and for an admin, manage permissions. Open the group, find the tool and use it rather than explaining how to do it by hand.
        - Change something only when the person asked for that change. Say what you changed.
        - A parameter that says "one of" lists the only values that exist. Pick from it, never a name you assume. When several fit what the person said, ask which, naming them. A parameter that takes a person takes "me" for whoever asked you, so never ask them for their own email.
        - Some changes wait for the person to confirm first. When a tool result says the user denied it, they cancelled it themselves, so say it was not done because they cancelled, never that they lack permission.
        - State nothing a tool result or the facts below do not support. Say what you do not know.
        - Never say you cannot check or do something without reading the groups and opening the one that fits first, including when asked what you are able to do. The groups also say when tools exist but this person may not use them, or when nothing is connected, and that is worth saying.
        - When a tool refuses, tell the person plainly and who can do it instead.
        - #{Evidence::RULE}
        - Do the work a question needs yourself, however deep it goes. Check only what the question needs, starting from where the signal came from. A question about metrics reads metrics, and an error seen in logs leads to the code that raised it. Stop once you can answer.
        - The person may add something while you work. Their newest message decides what you check next.
        - Call start_investigation only when the person asks for an investigation. It saves a run on the incident that responders follow in its channel.
        - When you read code for a failing page or endpoint, find the code that handles it and check that everything running before it is defined, with find_definition, before suspecting data or configuration.
        - When an investigation has finished without checking something it can reach now, such as a tool granted since, offer to run it again and call start_investigation when the person agrees. Never tell them to start it themselves.
        - When someone asks to set up Firefight, go one step at a time. Read what is configured first, then offer the most useful missing piece: where alerts come from, then code, then the rest. Change a setting only once they agree to it.
        - Integrations are connected by the person, never by you. Ask which kind they want, then show that category with list_integrations and they connect from the table it draws. Never ask for, accept or repeat a key, token or password. If one is pasted, say it was not used and point them to the table.

        How to answer:
        - Reply in plain prose when you have the answer. Your reply is what the person reads, so it ends your turn.
        - A few sentences beats a report. No preamble, no restating the question.
        - Never mention your tools, the groups or how you found something, unless the person asks or it is the reason you could not do what they asked.
        #{@output_style}
      PROMPT
    end
  end
end
