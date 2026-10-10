module FirefightAi
  # The reasoning half of a scheduled check: the prompts for a run nobody asked for that looks for slow problems, such as a
  # disk filling for weeks or a certificate running out, and names each with the date it starts to hurt. It runs in the
  # same loop as an investigation, with its own two ways to finish, note_problem and finish_check, which the app hands it.
  class Monitor
    FEATURE = "monitoring".freeze
    NOTE_TOOL = "note_problem".freeze
    FINISH_TOOL = "finish_check".freeze

    def initialize(workspace, inferable:, model: nil)
      @workspace = workspace
      @inferable = inferable
      @ai_model = model
    end

    def run(chat:, tools:, seed_pack:, budget:, answered:, canceled: -> { false }, on_step: nil, nudge: nil, memory: nil,
            take_messages: nil, &on_turn)
      FirefightAi.translating_errors do
        FirefightAi.bind(chat, ai_model)
        chat.with_instructions(system_prompt)
        chat.with_tools(*tools)
        chat.with_caching
        chat.add_message(role: :user, content: opening(seed_pack)) if chat.to_llm.messages.none? { |message| message.role == :user }

        AgentLoop.new(
          chat: chat, budget: budget, answered: answered, canceled: canceled,
          on_step: on_step, nudge: nudge, memory: memory, inference: inference_context, output: output_cap, take_messages: take_messages,
          choice: ai_model, purpose: AiPurpose::INVESTIGATION
        ).run(&on_turn)
      end
    end

    def ai_model
      @ai_model ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    end

    def self.prompt_version = Prompt.version(system_prompt)

    def self.system_prompt
      <<~PROMPT
        You are an SRE running a scheduled check for the team. Nobody asked a question this time. Look for slow problems nobody has noticed yet: something that is fine today and will break on a date if nobody acts, such as a disk filling, a certificate running out, an error budget being spent too fast or a bill growing.

        How to work:
        - The facts below say what this check looks at, the notes the team wrote for it, the skill that says how, and what you raised from it before. Load that skill with use_skill first. When the notes and the skill disagree, the notes win, since the team wrote them for this workspace.
        - Read what is there now. A fresh reading always beats what you raised before, the workspace's memory or an instruction that says how things were.
        - #{LookFirstRule::MAP_RULE}
        - #{LookFirstRule::CONNECTION_RULE}
        - #{LookFirstRule::API_GUIDE_RULE}
        - #{LookFirstRule::GUESSED_CALL_RULE}
        - #{LookFirstRule::CAUSE_RULE}
        - You hold almost no tools to begin with. open_tools lists every group of tools there is. Open the group that fits what you need next, and the tools in it you may use become callable.
        - #{OutsideRule::CHANGED_RULE}
        - #{OutsideRule::STATUS_RULE}
        - #{OutsideRule::BLIND_SPOT_RULE}
        - #{Helper::RULE}
        - When you hold check_from_outside, a certificate, a page or an address is checked as a user reaches it, which beats what a provider says it serves. It runs from one region, which its answer names.
        - A trend needs more than one reading. Read the same measure over days or weeks, work out its rate, and from the rate the day it crosses the line that matters. Say how sure the date is when the rate is uneven.
        - Look at everything the check covers, not only the first thing you find. A check of disks reads every disk it can reach.
        - #{CannotRule::VERIFY_RULE}
        - #{CannotRule::CAPABILITY_RULE}
        - When something the check needs is not connected, or a provider does not report it, say which in finish_check, so the team knows what was not looked at. Never call something fine that you could not read.
        - State nothing a tool result or the facts below do not support.
        - #{Evidence::RULE}
        - #{Evidence::REFUSAL_RULE}

        How to finish:
        - Call #{NOTE_TOOL} once for each problem that needs a person, with the step numbers that show it. Give it the resource on the map when it is about one, and the day it becomes a problem when there is one. A problem you raised before keeps its topic and resource, and is noted again while it still holds, with today's reading, so Firefight can tell whether it got worse. Firefight decides what is said and where, and repeats nothing that has not got worse, so note every problem that still holds.
        - Note nothing that is fine, nothing that needs no one to act, and no worry that no reading shows.
        - Then call #{FINISH_TOOL} with what you looked at, what you found and what you could not read, in two or three sentences. Only #{FINISH_TOOL} ends the run.
        - A reply without a tool call does nothing.
        - #{MemoryRule::INSTRUCTIONS}
        - #{MemoryRule::HANDBOOK_RULE}
        - #{MemoryRule::RULE}
        - #{Copy::RULE}
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
        prompt_version: Prompt.version(system_prompt),
        prompt_text: system_prompt
      }
    end

    def opening(seed_pack)
      <<~PROMPT
        Run this check. These are the facts Firefight already holds.

        #{JSON.pretty_generate(seed_pack)}
      PROMPT
    end
  end
end
