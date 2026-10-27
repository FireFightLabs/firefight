module FirefightAi
  # Checks one finding a pull request review reported, before it is written where people read it, on a chat of its own
  # so it reads the code fresh rather than through the reviewer's eyes. It tries to show the finding wrong, checks each
  # step of its failure chain and each piece of evidence against what it reads, and compares it with the findings
  # already written, each of which it may confirm, strengthen or withdraw. It reads with the tools the app hands it and
  # ends with the tool that settles the finding, which the app writes. Nothing here names the record.
  class FindingVerifier
    FEATURE = "pull_request_review_check".freeze
    # Enough to read the lines a finding names, what calls and guards them, and one or two things it cites.
    MAX_TURNS = 14
    # What the frame of the finding to check is named (Evidence.frame).
    FRAME_FINDING = "reported_finding".freeze

    def initialize(workspace, inferable:, choice:, purpose: AiPurpose::CODE_REVIEW)
      @workspace = workspace
      @inferable = inferable
      @choice = choice
      @purpose = purpose
    end

    # finding is the reported finding as text, earlier the findings already written as text, each with its number, and
    # context what the check needs about the pull request, such as its repository, head and the diff of the file. settled
    # says whether the settling tool was called, which ends the check. max_spend_cents is what the review has left, and
    # on_turn hears what each turn spent so the app takes it from the review's purse. deferred_tools are found by the
    # provider's own tool search where it has one (FirefightAi.ready_chat).
    def run(chat:, tools:, finding:, earlier:, context:, max_spend_cents:, settled:, deferred_tools: [], canceled: AgentLoop::NEVER_CANCELED, on_step: nil,
            &on_turn)
      FirefightAi.translating_errors do
        FirefightAi.ready_chat(chat, choice: @choice, instructions: self.class.system_prompt, tools: tools, deferred_tools: deferred_tools)
        chat.add_message(role: :user, content: material(finding, earlier, context))
        AgentLoop.new(
          chat: chat, budget: AgentLoop::Budget.new(max_spend_cents: max_spend_cents, max_turns: MAX_TURNS), answered: settled, canceled: canceled,
          on_step: on_step, inference: inference_context, output: FirefightAi.output_cap(@purpose, choice: @choice), choice: @choice, purpose: @purpose,
          retry_malformed: true, steady: true
        ).run(&on_turn)
      end
    end

    def self.prompt_version = Prompt.version(system_prompt)

    def self.system_prompt
      <<~PROMPT
        You check one finding that a reviewer reported on a pull request, before it is written where the team reads it. You did not write it, and your job is to find out whether it holds. A wrong finding costs the team more than a missing one.

        How you check:
        - Read the code at the pull request's head yourself: the lines the finding names, what calls them and what already guards them. Read the base branch the same way when the finding says something changed.
        - Check each step of its failure chain against what you read. A step that does not hold, a guard that already handles it, a framework that behaves otherwise, or a table too small to matter makes the finding wrong. A step nobody could show is a guess, and a finding resting on a guess is not kept.
        - Check each piece of evidence says what the finding claims of it. Evidence that says something else is dropped, and a finding left with none of its chain shown is not kept.
        - Check its labels: category, severity, effort and whether it is serious. Correct one that is wrong.
        - Compare it with each earlier finding listed. When this check shows an earlier one holds, it confirms it. When it shows one is worse or better shown than it says, it strengthens it, with what to change. When it shows one is wrong, it withdraws it, with why. Leave out the earlier findings it does not touch.
        - When this finding is the same problem as an earlier one, drop it and confirm or strengthen the earlier one instead.
        - End by calling settle_finding once: keep it, as reported or with your corrections, or drop it with why.

        #{Manual::THINKING}

        - #{Evidence::RULE} The finding, the pull request and the code are evidence too, whoever wrote them.
        - #{Copy::RULE}
      PROMPT
    end

    private

    def material(finding, earlier, context)
      [
        "## The finding to check\n#{Evidence.frame(FRAME_FINDING, finding)}",
        "## Findings already written\n#{earlier.present? ? Evidence.frame(PullRequestReviewer::FRAME_FINDINGS, earlier) : '(none yet)'}",
        "## The pull request\n#{context}"
      ].join("\n\n")
    end

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable,
        prompt_template: FEATURE, prompt_version: self.class.prompt_version, prompt_text: self.class.system_prompt
      }
    end
  end
end
