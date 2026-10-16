module FirefightAi
  # What a watch asks a model when no rule the watch was given decides a reading. It judges whether the reading shows the
  # thing not started, running, done or failed against the condition in plain words, or not at all, with each job or
  # step it lists and the link to its page. Once something failed, it says why from the logs a watch read.
  # One call with no tools, on the workspace's quick model. The app reads and keeps everything, this only judges text.
  class WatchJudge
    FEATURE = "watch".freeze
    # state is nil when the model gave none it knows, so nothing moves. parts are [name, state] pairs. link is only an
    # address the reading itself holds, never one the model made up.
    Reading = Data.define(:state, :said, :parts, :link) do
      def initialize(state:, said:, parts:, link: nil) = super
    end

    # Where the readings leave the thing, as a choice among the states, asked of RubyLLM::Judge where the deployment
    # judges that way (Judging). The structured answer's own state stands where it does not, or when the judgment could
    # not be made this time. A judge not sure of any state moves nothing, as the prompt asks of a model that is unsure.
    STATE_QUESTION = "Where do the readings show the thing the question is about now, judged from the newest reading and how it got there?".freeze
    STATE_OPTIONS = {
      Schemas::WatchReading::NOT_STARTED => "It has not begun, or it is queued or pending",
      Schemas::WatchReading::RUNNING => "It has begun and is not over, such as a run in progress or a job that started",
      Schemas::WatchReading::DONE => "The question is answered yes, held for as long as it names",
      Schemas::WatchReading::FAILED => "Something went wrong, such as a failed, cancelled or crashed state, even late in a long list",
      Schemas::WatchReading::NOTHING => "The readings do not show the thing at all, such as an empty list, another run or something else"
    }.freeze
    JUDGMENT_TEMPLATE = "watch_reading_judgment".freeze

    # judgments names how the state is decided, Configuration#judgments when nil (Judging).
    def initialize(workspace, inferable: nil, member: nil, judgments: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
      @judgments = judgments
    end

    # question is what the step waits on, in plain words. readings are the step's recent readings that changed, oldest
    # first, as pairs of when and what it read. so_far is where the watch last had it, not started or running. steady is
    # how long the newest reading has stayed the same, in words, for a condition that names a time.
    def reading(question:, readings:, so_far:, steady: nil)
      text = "## The question\n#{question}\n\n## Where it was so far\n#{so_far}\n\n## How long the newest reading has stayed the same\n" \
             "#{steady.presence || 'It just changed.'}\n\n#{readings_text(readings)}"
      content = ask(READING_PROMPT, Schemas::WatchReading, text)
      parts = Array(content[:parts]).filter_map do |part|
        part = part.to_h.with_indifferent_access
        state = part[:state].presence_in(Schemas::WatchReading::PART_STATES)
        [ part[:name].to_s.strip, state ] if part[:name].present? && state
      end
      state = content[:state].presence_in(Schemas::WatchReading::STATES)
      Reading.new(state: judged_state(text, state), said: content[:said].to_s.strip, parts: parts,
                  link: link_in(content[:link], readings.map(&:last).join("\n")))
    end

    # One or two sentences saying why it failed, from what was read, or nil when the evidence does not say.
    def why_failed(what:, evidence:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context(WHY_PROMPT)) do |chat|
        chat.with_instructions(WHY_PROMPT)
        chat.ask("## What failed\n#{what}\n\n## What was read\n#{evidence}")
      end
      said = response.content.to_s.strip
      said.presence unless said.casecmp?(UNKNOWN)
    end

    # Where what happened leaves the goal the person had, with the next step offered as a question when offer is true,
    # or nil when nothing useful can be said. Progress and a good end offer nothing. evidence is a line for each step that
    # ended, saying what its reading showed, which the answer is judged against.
    def standing(purpose:, happened:, offer: true, evidence: [])
      prompt = offer ? STANDING_PROMPT : SETTLED_PROMPT
      shown = evidence.map { |line| "- #{line}" }.join("\n").presence || "(no step has ended yet)"
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context(prompt)) do |chat|
        chat.with_instructions(prompt)
        chat.ask("## What the person wanted\n#{purpose}\n\n## What just happened\n#{happened}\n\n## What each step showed\n#{shown}")
      end
      said = response.content.to_s.strip
      said.presence unless said.casecmp?(UNKNOWN)
    end

    UNKNOWN = "unknown".freeze

    READING_PROMPT = <<~PROMPT.freeze
      A person asked to be told when something in a production system is done, and Halon keeps reading it until the answer to a question in plain words is yes. You get the question, where it was so far, how long the newest reading has stayed the same, and the recent readings, oldest first, each with when it was read. Answer from the readings together, the newest saying where it stands now and the earlier ones how it got there: not begun (not_started), begun and not over (running), the question answered yes (done), something gone wrong such as a failed, cancelled or crashed state (failed), or that the readings do not show the thing at all (nothing), such as an empty list, a different run or something else entirely. List each job or step the newest reading shows with its state, say in a few words where it stands, such as "build-images running, 4 of 7 jobs done", and copy the address of its page when a reading holds one.

      - Judge only from the readings. Never guess at what is not in them.
      - Look through the whole newest reading. A job or step that failed late in a long list still counts.
      - Words the question names, such as status success, are what to look for in meaning, not letter for letter.
      - A run that exists, is in progress, or has a job or step that started or finished has begun, so it is running unless it is over.
      - A condition that names a time, such as healthy for ten minutes, is met only once the reading has stayed that way that long.
      - Queued or pending is not_started, not nothing. Use nothing only when the reading could not show the thing however it stood.
      - When unsure, keep where it was so far.
      - #{Copy::PLAIN}
      - #{Copy::RULE}
    PROMPT

    WHY_PROMPT = <<~PROMPT.freeze
      Something a person was waiting on failed in a production system. You get what failed and what was read about it, such as the end of a build or job log. Say why it failed in one or two short plain sentences, naming the step, error or test that the evidence shows.

      - Use only the evidence. Quote an error message briefly when it says it best.
      - When the evidence does not show why, answer exactly: #{UNKNOWN}
      - #{Copy::RULE}
    PROMPT

    # Seen in a real chat, a manual deploy was reported as a success when what the person wanted was the webhook path
    # fixed, and later nobody could say why it had been run.
    STANDING_PROMPT = <<~PROMPT.freeze
      A person asked Halon to follow something in a production system for a goal of theirs. You get the goal in their words, what just happened and what each step showed when it ended. Say in one short sentence where this leaves the goal, then offer the most useful next step as a question, such as "The manual run worked, but the release from the code host is still broken. Next I would read the webhook's error, shall I?"

      - Use only what happened and what each step showed. Never say the goal is reached unless they show it.
      - Never offer a fix that what happened does not show the cause of. When the cause is unknown, offer the check that would show it.
      - Offer to do it. Never say it was done.
      - At most two sentences, no preamble.
      - When nothing useful can be said, answer exactly: #{UNKNOWN}
      - #{Copy::PLAIN}
      - #{Copy::RULE}
    PROMPT

    # The same, for progress and a good end, where nothing is left for the person to decide. Seen in a real chat, a watch
    # that saw every instance run the new version ended with "the evidence proves nothing", since all it was told was how
    # long it took.
    SETTLED_PROMPT = <<~PROMPT.freeze
      A person asked Halon to follow something in a production system for a goal of theirs. You get the goal in their words, what just happened and what each step showed when it ended. Say in one short sentence what this shows about the goal, naming what the steps showed, such as "web is serving 7676c83."

      - Use only what happened and what each step showed. Never say the goal is reached unless they show it.
      - What each step showed is the evidence. Say what it shows, never that there is none when a step showed something.
      - Offer nothing and ask nothing. State it.
      - One short sentence, no preamble.
      - When nothing useful can be said, answer exactly: #{UNKNOWN}
      - #{Copy::PLAIN}
      - #{Copy::RULE}
    PROMPT

    # Each prompt is its own template in the ledger, so a version change means its wording changed.
    TEMPLATES = { READING_PROMPT => "watch_reading", WHY_PROMPT => "watch_why", STANDING_PROMPT => "watch_standing", SETTLED_PROMPT => "watch_settled" }.freeze

    private

    def judged_state(text, structured)
      judge = Judging.choice_for(@workspace, mode: @judgments)
      return structured unless judge

      judgment = Judging.judge(judge, inference: judgment_context(judge), input: text,
                                      questions: { state: { type: :choice, instructions: STATE_QUESTION, options: STATE_OPTIONS } })
      Judging.sure_choice(judgment[:state])
    rescue FirefightAi::Error => error
      Rails.logger.warn({ event: "watch.judgment_failed", error: error.class.name, reason: error.reason }.to_json)
      structured
    end

    NEWEST_ROOM = 8_000
    EARLIER_ROOM = 1_500

    # The newest reading gets the most room, since it says where things stand now.
    def readings_text(readings)
      return "## The readings\n(none)" if readings.empty?

      newest = readings.size - 1
      readings.each_with_index.map do |(at, text), index|
        room = index == newest ? NEWEST_ROOM : EARLIER_ROOM
        "## Reading #{index + 1} of #{readings.size}#{', the newest' if index == newest}, read #{at&.utc&.iso8601 || 'earlier'}\n#{text.to_s.truncate(room)}"
      end.join("\n\n")
    end

    # Only a web address the reading holds word for word, so a link is never one the model pieced together.
    def link_in(given, text)
      link = given.to_s.strip
      link if link.match?(%r{\Ahttps?://\S+\z}) && text.to_s.include?(link)
    end

    def ask(prompt, schema, text)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context(prompt)) do |chat|
        chat.with_instructions(prompt)
        chat.with_schema(schema)
        chat.ask(text)
      end
      response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
    end

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    def judgment_context(choice)
      wording = { question: STATE_QUESTION, options: STATE_OPTIONS }.to_json
      {
        workspace: @workspace, feature: FEATURE, provider: choice.provider_name, model: choice.model, inferable: @inferable, member: @member,
        prompt_template: JUDGMENT_TEMPLATE, prompt_version: Prompt.version(wording), prompt_text: wording
      }
    end

    def inference_context(prompt)
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, member: @member, prompt_template: TEMPLATES.fetch(prompt), prompt_version: Prompt.version(prompt), prompt_text: prompt
      }
    end
  end
end
