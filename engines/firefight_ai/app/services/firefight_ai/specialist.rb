module FirefightAi
  # Reads one kind of system for Halon, such as databases or deploys, with only that kind's reads, and reports what it
  # found with the lines and links that show it and any change it would make. Halon decides on a change, and the person
  # confirms it, so a specialist never makes one. The app hands over the tools, the playbook and the tool that takes the
  # report, and keeps the record, so nothing here names whose permissions it reads with.
  class Specialist
    FEATURE = "specialist".freeze
    # Enough to read a kind of system several ways and follow one lead, never a whole investigation.
    MAX_TURNS = 16

    # choice is the ModelChoice the app picked, the quick model or the main one. purpose is what the ledger and the
    # output cap read it as.
    def initialize(workspace, inferable:, choice:, purpose:, member: nil)
      @workspace = workspace
      @inferable = inferable
      @choice = choice
      @purpose = purpose
      @member = member
    end

    # The app has already saved the objective as the chat's first message. playbook is how this kind of system is read,
    # added to the instructions. answered says whether the report was taken, which ends the run. A plain reply ends it
    # too. max_spend_cents and on_turn are as for a helper.
    def run(chat:, tools:, playbook:, max_spend_cents:, canceled:, answered:, on_step: nil, memory: nil, &on_turn)
      FirefightAi.translating_errors do
        FirefightAi.ready_chat(chat, choice: @choice, instructions: "#{self.class.template_text}\n#{playbook}", tools: tools)

        AgentLoop.new(
          chat: chat, budget: AgentLoop::Budget.new(max_spend_cents: max_spend_cents, max_turns: MAX_TURNS),
          answered: answered, canceled: canceled, reply_is_answer: true, on_step: on_step, memory: memory,
          inference: inference_context, output: FirefightAi.output_cap(@purpose, choice: @choice), choice: @choice, purpose: @purpose,
          retry_malformed: true
        ).run(&on_turn)
      end
    end

    def self.prompt_version = Manual.version(template_text)

    def self.template_text
      <<~PROMPT
        You are one of Halon's specialists. Halon is working with a person on something larger and asked you about the one kind of system you read. Read it until you can answer Halon's objective with evidence, then report.

        How you work:
        - Stay inside the objective. Something outside it that looks important gets one finding of its own.
        - Read as many ways as the objective needs, and stop once it is answered. Say plainly when you found nothing.
        - Every tool you may use is in your hands from the start, and each only reads. search_docs and read_doc read a connected provider's documentation.
        - #{Evidence::RULE}

        #{Manual::THINKING}

        How you report:
        - End by calling report_findings once. Each finding is a claim with the exact lines from the results that show it, copied as they appear, and the links those results gave. Halon cites them, so a line or a link you did not read is refused.
        - A change you would make goes in proposed_changes as the exact tool, its arguments and the reads that justify it. You never make it yourself. Halon decides, and the person confirms it.
        - Put what you could not check, and why, in not_checked.
        - #{Copy::WRITING}
      PROMPT
    end

    private

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: @choice.provider_name, model: @choice.model, inferable: @inferable, member: @member,
        prompt_template: FEATURE, prompt_version: self.class.prompt_version, prompt_text: Manual.recorded(self.class.template_text)
      }
    end
  end
end
