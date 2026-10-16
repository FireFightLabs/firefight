module FirefightAi
  # The reasoning half of an investigation: the prompts, the model, and the loop around them.
  class Investigator
    FEATURE = "investigation".freeze

    # What the first conclude of a run is answered with. The same agent argues with its own answer, and may only run a
    # check it can name, so a critic told to find fault cannot make doubt up.
    CRITIQUE = "Not recorded yet. Before it is, try to prove it wrong. For each claim, name the check that would show it " \
               "false. If you can name one you have not run, run it now and record what it shows against the theory. Let " \
               "only a result you read change the answer. Then call conclude again, changed or not.".freeze

    ROLE = "You are Halon, the SRE on this team, investigating a problem in production for the team that owns it. It is " \
           "either a declared incident or a question someone asked before anyone declared one. Answer what was asked, " \
           "starting from the facts in the first message and from where the signal came from, and stop once the evidence " \
           "answers it.".freeze

    # How a run is recorded and how it ends, which only a run has.
    RUN = <<~TEXT.strip.freeze
      How a run works:
      - Every tool result carries a step number, which is how you cite what you saw.
      - Record each theory with record_hypothesis as you form it, and settle it with the steps that showed it.
      - conclude ends the run, and its description says what it takes. A wrong answer costs the team more than an honest "the evidence does not show a cause yet".
      - Your answer is read first in a busy channel by people who may not read code, so give it the way you would tell the whole team: what kind of answer it is and how sure you are, what is wrong in one plain sentence, a few short facts behind it, and the fix in a sentence. The summary, each claim and the fix's steps carry the detail, the code and the names, for whoever reads on.
    TEXT

    # model is a ModelChoice for a run told to use one, such as a rehearsal comparing models. nil means the workspace's.
    def initialize(workspace, inferable:, member: nil, model: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @ai_model = model
    end

    # deferred_tools are found by the provider's own tool search where it has one (FirefightAi.ready_chat). on_backup goes
    # to the loop, see AgentLoop.
    def run(chat:, tools:, seed_pack:, budget:, answered:, deferred_tools: [], canceled: -> { false }, on_step: nil, nudge: nil,
            memory: nil, take_messages: nil, purse: nil, on_backup: nil, &on_turn)
      FirefightAi.translating_errors do
        # One agent resends everything it has read on every turn, so the provider is asked to cache it.
        FirefightAi.ready_chat(chat, choice: ai_model, instructions: system_prompt, tools: tools, deferred_tools: deferred_tools)
        open_with(chat, seed_pack)

        AgentLoop.new(
          chat: chat, budget: budget, answered: answered, canceled: canceled,
          on_step: on_step, nudge: nudge, memory: memory, inference: inference_context, output: output_cap, take_messages: take_messages,
          choice: ai_model, purpose: AiPurpose::INVESTIGATION, purse: purse, on_backup: on_backup, steady: true
        ).run(&on_turn)
      end
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    # The prompt as deployed. Nothing in it changes from run to run, so its digest names this version of Halon.
    def self.prompt_version = Manual.version(system_prompt)

    def self.system_prompt
      <<~PROMPT
        #{ROLE}

        #{RUN}

        #{Manual::THINKING}

        #{Manual::PEOPLE}

        #{Manual::DONE}

        #{Manual::RUN_TOOLS}

        #{Manual::PLAYBOOKS}

        #{Manual::WRITING}
      PROMPT
    end

    private

    def output_cap = FirefightAi.output_cap(AiPurpose::INVESTIGATION, choice: ai_model)

    def system_prompt = self.class.system_prompt

    def inference_context
      {
        workspace: @workspace,
        feature: FEATURE,
        provider: ai_model.provider_name,
        model: ai_model.model,
        inferable: @inferable,
        member: @member,
        prompt_template: FEATURE,
        prompt_version: self.class.prompt_version,
        prompt_text: Manual.recorded(system_prompt)
      }
    end


    # The facts never change during a run, so they end in a cache boundary of their own, after the instructions'.
    def open_with(chat, seed_pack)
      return if chat.to_llm.messages.any? { |message| message.role == :user }

      chat.add_message(role: :user, content: opening(seed_pack), cache_until_here: true)
    end

    def opening(seed_pack) = Facts.opening("Investigate this. These are the facts Firefight already holds.", seed_pack)
  end
end
