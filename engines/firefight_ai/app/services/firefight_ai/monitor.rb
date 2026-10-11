module FirefightAi
  # The reasoning half of a scheduled check: the prompts for a run nobody asked for that looks for slow problems, such as a
  # disk filling for weeks or a certificate running out, and names each with the date it starts to hurt. It runs in the
  # same loop as an investigation, with its own two ways to finish, note_problem and finish_check, which the app hands it.
  class Monitor
    FEATURE = "monitoring".freeze
    NOTE_TOOL = "note_problem".freeze
    FINISH_TOOL = "finish_check".freeze

    ROLE = "You are Halon, the SRE on this team, running a scheduled check. Nobody asked a question this time. Look for " \
           "slow problems nobody has noticed yet: something that is fine today and will break on a date if nobody acts, " \
           "such as a disk filling, a certificate running out, an error budget being spent too fast or a bill growing.".freeze

    # How a check is run and how it ends, which only a check has.
    CHECKING = <<~TEXT.strip.freeze
      How a check works:
      - The facts say what this check looks at, the notes the team wrote for it, the skill that says how, and what you raised from it before. Load that skill with use_skill first. Where the notes and the skill differ, follow the notes, since the team wrote them for this workspace.
      - #{NOTE_TOOL} records each problem that needs a person, and #{FINISH_TOOL} ends the run. Their descriptions say what each takes.
    TEXT

    def initialize(workspace, inferable:, model: nil)
      @workspace = workspace
      @inferable = inferable
      @ai_model = model
    end

    # deferred_tools are found by the provider's own tool search where it has one (FirefightAi.ready_chat). purse and
    # on_backup go to the loop, as an investigation's do, see AgentLoop.
    def run(chat:, tools:, seed_pack:, budget:, answered:, deferred_tools: [], canceled: -> { false }, on_step: nil, nudge: nil,
            memory: nil, take_messages: nil, purse: nil, on_backup: nil, &on_turn)
      FirefightAi.translating_errors do
        FirefightAi.ready_chat(chat, choice: ai_model, instructions: system_prompt, tools: tools, deferred_tools: deferred_tools,
                                     cache_ttl: FirefightAi::LONG_CACHE)
        if chat.to_llm.messages.none? { |message| message.role == :user }
          chat.add_message(role: :user, content: opening(seed_pack), cache_until_here: true, cache_ttl: FirefightAi::LONG_CACHE)
        end

        AgentLoop.new(
          chat: chat, budget: budget, answered: answered, canceled: canceled,
          on_step: on_step, nudge: nudge, memory: memory, inference: inference_context, output: output_cap, take_messages: take_messages,
          choice: ai_model, purpose: AiPurpose::INVESTIGATION, purse: purse, on_backup: on_backup
        ).run(&on_turn)
      end
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    def self.prompt_version = Manual.version(system_prompt)

    def self.system_prompt
      <<~PROMPT
        #{ROLE}

        #{CHECKING}

        #{Manual::THINKING}

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
        member: nil,
        prompt_template: FEATURE,
        prompt_version: self.class.prompt_version,
        prompt_text: Manual.recorded(system_prompt)
      }
    end

    def opening(seed_pack) = Facts.opening("Run this check. These are the facts Firefight already holds.", seed_pack)
  end
end
