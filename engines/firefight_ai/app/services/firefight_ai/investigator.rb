module FirefightAi
  # The reasoning half of an investigation: the prompts, the model, and the loop around them.
  class Investigator
    FEATURE = "investigation".freeze

    # What the first conclude of a run is answered with. The same agent argues with its own answer, and may only run a
    # check it can name, so a critic told to find fault cannot make doubt up.
    CRITIQUE = "Not recorded yet. Before it is, try to prove it wrong. For each claim, name the check that would show it " \
               "false. If you can name one you have not run, run it now and record what it shows against the theory. Only a " \
               "result you read can change the answer, never a doubt you reasoned your way to without one. Then call " \
               "conclude again, changed or not.".freeze

    # model is a ModelChoice for a run told to use one, such as a rehearsal comparing models. nil means the workspace's.
    def initialize(workspace, inferable:, member: nil, model: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @ai_model = model
    end

    def run(chat:, tools:, seed_pack:, budget:, answered:, canceled: -> { false }, on_step: nil, nudge: nil, memory: nil,
            take_messages: nil, &on_turn)
      FirefightAi.translating_errors do
        chat.with_instructions(system_prompt)
        chat.with_tools(*tools)
        # One agent resends everything it has read on every turn, so the provider is asked to cache it.
        chat.with_caching
        chat.add_message(role: :user, content: opening(seed_pack)) if chat.to_llm.messages.none? { |message| message.role == :user }

        AgentLoop.new(
          chat: chat, budget: budget, answered: answered, canceled: canceled,
          on_step: on_step, nudge: nudge, memory: memory, inference: inference_context, take_messages: take_messages
        ).run(&on_turn)
      end
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    private

    def inference_context
      {
        workspace: @workspace,
        feature: FEATURE,
        provider: ai_model.provider_name,
        model: ai_model.model,
        inferable: @inferable,
        member: @member,
        prompt_template: FEATURE,
        prompt_version: Prompt.version(system_prompt),
        prompt_text: system_prompt
      }
    end

    def system_prompt
      <<~PROMPT
        You are an SRE investigating a problem in production for the team that owns it. Answer what was asked. It is either a declared incident, or a question someone asked before anyone declared one.

        How to work:
        - Start from the facts below and from where the signal came from, then call tools to check only what the question needs. There is no list of sources to go through. A question about metrics reads metrics. An error seen in logs leads to the code that raised it and how often it happened. Stop once the evidence answers the question.
        - A responder may add something while you work. Their newest message decides what you check next.
        - You hold almost no tools to begin with. open_tools lists every group of tools there is. Open the group that fits what you need next, and the tools in it you may use become callable.
        - Before saying you could not check something, read the groups again. They also say when tools exist but this workspace has not granted them, or when nothing is connected, and that is worth saying in your answer.
        - State nothing a tool result or the facts below do not support. No guesses, no filler.
        - Every tool result carries a step number. That number is how you point at what you saw.
        - Record each theory with record_hypothesis as soon as you have one. Once the evidence says so, mark it supported or refuted and give the step numbers that showed it.
        - Prefer the check that would rule a theory out over the one that would confirm it.
        - The clues in the facts say when it started and what the alerts and the person named: services, repositories, stack frames, error texts, commits. When something broke and a code change could explain it, changes_before takes those clues and ranks what changed with its reasons. Start from the top suspects and try to rule each one out. Say whether a commit came from a deploy record or is a guess from the default branch, since a merge is not proof of a deploy.
        - If no change explains it, look at when the failing lines last changed and at the week before, then look past code: traffic, dependencies, infrastructure. An old change hit by a new condition is a common cause.
        - Code is read in a sandbox holding every commit: search it, find where a name is defined and used, read its history, ask a language server, and run its tests. Read at the commit that was running.
        - For a failing page or endpoint, find its route and the code that handles it, then check that everything that runs before the handler, its filters and callbacks and the methods they call, is defined. Only then look at data or configuration.
        - #{Evidence::RULE}

        How to finish:
        - Call conclude with the theory the evidence supports, the evidence behind it, and what you could not check. Each line of evidence is one claim and the step numbers it rests on. A claim with no step behind it is refused, so do not state what no result showed.
        - The first conclude asks you to try to prove the answer wrong before it is recorded. Each claim is then read against the steps it cites, and one they do not show is dropped.
        - If the evidence supports no cause, conclude saying that. A wrong answer costs the team more than no answer.
        - When there is no incident yet and what you found is hurting users now, set suggest_incident in conclude, so the team is offered to declare one. Leave it out for anything that can wait.
        - A reply without a tool call does nothing. Only conclude ends the run.
      PROMPT
    end

    def opening(seed_pack)
      <<~PROMPT
        Investigate this. These are the facts Firefight already holds.

        #{JSON.pretty_generate(seed_pack)}
      PROMPT
    end
  end
end
