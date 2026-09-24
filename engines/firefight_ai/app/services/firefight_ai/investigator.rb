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

    def initialize(workspace, inferable:, member: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
    end

    def run(chat:, tools:, seed_pack:, budget:, answered:, canceled: -> { false }, on_step: nil, nudge: nil, memory: nil, &on_turn)
      FirefightAi.translating_errors do
        chat.with_instructions(system_prompt)
        chat.with_tools(*tools)
        # One agent resends everything it has read on every turn, so the provider is asked to cache it.
        chat.with_caching
        chat.add_message(role: :user, content: opening(seed_pack)) if chat.to_llm.messages.none? { |message| message.role == :user }

        AgentLoop.new(
          chat: chat, budget: budget, answered: answered, canceled: canceled,
          on_step: on_step, nudge: nudge, memory: memory, inference: inference_context
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
        You are an SRE investigating an incident for the team responding to it. Find what caused it.

        How to work:
        - Start from the facts below, then call tools to check what you cannot see yet.
        - You hold almost no tools to begin with. open_tools lists every group of tools there is. Open the group that fits what you need next, and the tools in it you may use become callable.
        - Before saying you could not check something, read the groups again. They also say when tools exist but this workspace has not granted them, or when nothing is connected, and that is worth saying in your answer.
        - State nothing a tool result or the facts below do not support. No guesses, no filler.
        - Every tool result carries a step number. That number is how you point at what you saw.
        - Record each theory with record_hypothesis as soon as you have one. Once the evidence says so, mark it supported or refuted and give the step numbers that showed it.
        - Prefer the check that would rule a theory out over the one that would confirm it.
        - The facts say where the clues point and what changed before it started, with suspects ranked and the reasons for each. Start from the top suspects and try to rule each one out. Say whether a commit came from a deploy record or is a guess from the default branch, since a merge is not proof of a deploy.
        - If no change in the window explains it, look at when the failing lines last changed and at the week before, then look past code: traffic, dependencies, infrastructure. An old change hit by a new condition is a common cause.
        - #{Evidence::RULE}

        How to finish:
        - Call conclude with the theory the evidence supports, the evidence behind it, and what you could not check. Each line of evidence is one claim and the step numbers it rests on. A claim with no step behind it is refused, so do not state what no result showed.
        - The first conclude asks you to try to prove the answer wrong before it is recorded. Each claim is then read against the steps it cites, and one they do not show is dropped.
        - If the evidence supports no cause, conclude saying that. A wrong answer costs the team more than no answer.
        - A reply without a tool call does nothing. Only conclude ends the run.
      PROMPT
    end

    def opening(seed_pack)
      <<~PROMPT
        Investigate this incident. These are the facts Firefight already holds.

        #{JSON.pretty_generate(seed_pack)}
      PROMPT
    end
  end
end
