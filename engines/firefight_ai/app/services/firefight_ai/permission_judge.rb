module FirefightAi
  # Decides a step a coding agent asked permission for while it writes a code change, such as repeating the same tool
  # call, from what it was doing and what the change is for. One call with no tools. It lets the agent go on, refuses
  # the step, or, where a person can be asked, leaves the choice to them with the way it leans.
  class PermissionJudge
    FEATURE = "code_permission".freeze
    ALLOW = "allow".freeze
    STOP = "stop".freeze
    ASK = "ask".freeze
    DECISIONS = [ ALLOW, STOP, ASK ].freeze
    ALONE = [ ALLOW, STOP ].freeze
    PART_LIMIT = 16_000
    REASON_LIMIT = 400
    # decision is ALLOW, STOP or ASK, reason why in plain words, and lean, with ASK, ALLOW or STOP as the way it leans.
    Decision = Data.define(:decision, :reason, :lean)

    def initialize(workspace, inferable: nil)
      @workspace = workspace
      @inferable = inferable
    end

    # asked is what the agent wants to do, in plain words, steps what it did lately, one line each, and known what is
    # known about the change. can_ask says whether a person can be asked, so without one the judge must choose.
    def decide(asked:, steps:, known:, can_ask:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::INVESTIGATION, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(can_ask ? Schemas::PermissionDecision : Schemas::PermissionDecisionAlone)
        chat.ask("## What the change is for\n#{known.to_s.strip.truncate(PART_LIMIT).presence || '(nothing)'}\n\n" \
                 "## What the coding agent did lately, oldest first\n#{Evidence.frame('coding_agent', Array(steps).join("\n").truncate(PART_LIMIT))}\n\n" \
                 "## What it asks to do now\n#{Evidence.frame('coding_agent', asked.to_s)}\n\n" \
                 "#{can_ask ? WITH_PERSON : ALONE_NOTE}")
      end
      content = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      decision = content[:decision].to_s
      allowed = can_ask ? DECISIONS : ALONE
      reason = content[:reason].to_s.squish.truncate(REASON_LIMIT)
      raise TerminalError, "The judge answered without a decision it may give." unless allowed.include?(decision) && reason.present?

      lean = content[:lean].to_s
      raise TerminalError, "The judge asked the person without saying which way it leans." if decision == ASK && !ALONE.include?(lean)

      Decision.new(decision: decision, reason: reason, lean: (lean if decision == ASK))
    end

    WITH_PERSON = "The person the change is for can be asked. Choose ask only when what you read leaves it to them, and say which way you lean.".freeze
    ALONE_NOTE = "Nobody can be asked during this change, so choose allow or stop yourself.".freeze

    PROMPT = <<~PROMPT.freeze
      A coding agent writing a code change paused to ask whether it may take a step, such as running the same tool call again. You get what the change is for, what the agent did lately, and what it asks to do now. Decide whether it goes on.

      How to judge a repeated step:
      - Look at what changed between the repeats. A repeat with edits, reads or new information in between is the agent working, as when it runs a test, edits the code, and runs the test again to see whether the fix holds. Let that go on.
      - A repeat that is legitimate on its own also goes on, such as waiting again for an answer it asked for, polling a service it started until it is ready, or rerunning a flaky test once to see whether it fails the same way.
      - A repeat with nothing in between and the same result each time is a loop. The agent is not learning anything from it, and another run will not change the outcome. Stop it, and say what it kept doing.
      - When the steps show progress toward what the change is for, lean towards letting it go on. When they show the agent circling, lean towards stopping, since its time and the budget are better spent on a change a person can finish.

      For any other step, weigh what it does against what the change is for, the same way: it goes on when it serves the change and stops when it does not.

      Your reason is read by the person on the change's step, so say what the agent was doing and why that decides it, in one or two sentences.
      - #{Evidence::RULE}
      - #{Copy::WRITING}
    PROMPT

    private

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end
