module FirefightAi
  # One narrow check Halon hands off while it works, run beside other helpers at the same time. It only reads, with the
  # tools the app hands it, and its plain reply is its report, which goes back to the loop that started it. The app keeps
  # the record and decides who it acts as, so nothing here names whose permissions it reads with.
  class Helper
    FEATURE = "helper".freeze
    # Enough to find the thing, read it two or three ways and say what it shows, never a whole investigation.
    MAX_TURNS = 12

    # choice is the ModelChoice the app picked for this helper, the side jobs' model or the main one for a deep check.
    def initialize(workspace, inferable:, choice:, purpose:, member: nil)
      @workspace = workspace
      @inferable = inferable
      @choice = choice
      @purpose = purpose
      @member = member
    end

    # The app has already saved the brief as the chat's first message. max_spend_cents is this helper's share of what the
    # asking loop has left, and on_turn hears what each turn spent so the app can take it from that loop's purse.
    # deferred_tools are found by the provider's own tool search where it has one (FirefightAi.ready_chat).
    def run(chat:, tools:, max_spend_cents:, canceled:, deferred_tools: [], on_step: nil, memory: nil, &on_turn)
      FirefightAi.translating_errors do
        FirefightAi.ready_chat(chat, choice: @choice, instructions: self.class.template_text, tools: tools, deferred_tools: deferred_tools)

        AgentLoop.new(
          chat: chat, budget: AgentLoop::Budget.new(max_spend_cents: max_spend_cents, max_turns: MAX_TURNS),
          answered: -> { false }, canceled: canceled, reply_is_answer: true, on_step: on_step, memory: memory,
          inference: inference_context, output: FirefightAi.output_cap(@purpose, choice: @choice), choice: @choice, purpose: @purpose,
          retry_malformed: true
        ).run(&on_turn)
      end
    end

    def self.prompt_version = Manual.version(template_text)

    def self.template_text
      <<~PROMPT
        You are one of Halon's helpers. Halon is working on something larger and handed you one narrow check, while other helpers check other things at the same time. Do this check and report back.

        How a check works:
        - Stay inside the brief. Something outside it that looks important gets one line in your report.
        - A few reads are enough. Stop as soon as the brief is answered.

        #{Manual::THINKING}

        #{Manual::RUN_TOOLS}

        How to report:
        - Reply with your report in plain text, at most five short lines: what you found, with the values you read and where they came from, then anything you could not check and why.
        - When results carry step numbers, end each finding with the steps it rests on, such as (steps 4, 6).
        - Say plainly when you found nothing, and keep to what the results show.
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
