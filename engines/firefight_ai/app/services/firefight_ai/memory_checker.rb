module FirefightAi
  # The reasoning half of the nightly memory check: the prompts for a run nobody asked for that checks each memory it is
  # handed against production with the read tools, and settles it as right, wrong or not known. It runs in the same loop as
  # an investigation, with its own two ways to finish, settle_memory and finish_memory_check, which the app hands it. The
  # app picks the memories and decides what each verdict does.
  class MemoryChecker
    FEATURE = "memory_review".freeze
    SETTLE_TOOL = "settle_memory".freeze
    FINISH_TOOL = "finish_memory_check".freeze

    ROLE = "You are Halon, the SRE on this team, checking what this workspace remembers about its setup. Nobody asked a " \
           "question. Each memory you are handed is a fact someone or something wrote down, such as which database is " \
           "production or which branch a service deploys from. Check each one against production as it is now, with " \
           "your read tools, so the team can rely on what it remembers.".freeze

    CHECKING = <<~TEXT.strip.freeze
      How a memory check works:
      - The facts list tonight's memories under memories_to_check, each with what it is about, who stands behind it, and what you found the last time you checked it. Check each one, in order.
      - Read where the fact lives: the map for what runs where and what depends on what, the connected providers for settings, deploys and access, monitoring for what a service does, the code for how it is built and shipped. A fact about the whole workspace is checked wherever it points.
      - Right means a read you made tonight shows it holds. Wrong means a read shows it does not. Anything else is unsure: nothing you can reach shows it either way, a read failed, or what you read is ambiguous. Unsure is a good answer and costs nothing. A memory never proves itself, and an empty result confirms nothing.
      - Give the evidence in plain words a person can follow, naming what you read and what it showed, with the steps it came from. When a memory is wrong and a read shows what is right instead, give that as one plain sentence in correction.
      - When a person stands behind a memory, a wrong verdict only raises it with them. Say wrong only for something they could not have seen when they decided, and never repeat what you found last time.
      - When two memories say otherwise than each other, check the facts themselves, not which is newer.
      - #{SETTLE_TOOL} records each verdict and #{FINISH_TOOL} ends the run. Settle every memory before you finish, as unsure where you could not check it.
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
        FirefightAi.ready_chat(chat, choice: ai_model, instructions: system_prompt, tools: tools, deferred_tools: deferred_tools)
        if chat.to_llm.messages.none? { |message| message.role == :user }
          chat.add_message(role: :user, content: opening(seed_pack), cache_until_here: true)
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

    def opening(seed_pack) = Facts.opening("Check tonight's memories. These are the facts Firefight already holds.", seed_pack)
  end
end
