# Runs a saved runbook, such as Release Firefight, once the person confirmed what it will do. Each step's tool runs as
# the person who asked, through the same tool a chat offers them, so grants, packs, approval rules and the activity log
# apply to each step exactly as if Halon had called it. The first step that is refused, waits for an approval or fails
# stops the run. When every step went through, the runbook's watch starts and reports back like any watch.
class Conversation::Tools::RunRunbook < RubyLLM::Tool
  NAME = "run_runbook".freeze
  RUNBOOK_ARG = "runbook".freeze
  INPUTS_ARG = "inputs".freeze
  # How much of each step's answer Halon reads back, enough to say what it started.
  ANSWER_LIMIT = 1_500
  # A step with no tool is left to a person, and the run says so rather than skipping it quietly.
  BY_HAND = "Left to you, Halon does not run it".freeze

  description "Run a saved runbook that has tool steps, such as Release Firefight, by its name, slug or another name it goes by " \
              "(search_runbooks says which are runnable). First tell the person what it will do and which inputs it uses, and " \
              "ask for any input it has no default for. The person confirms the whole run before anything happens. Each step " \
              "runs as them with their permissions, the run stops at the first step that is refused, waits for an approval or " \
              "fails, and once every step went through its watch starts and reports back here."

  def self.tool_name = NAME

  def initialize(turn)
    super()
    @turn = turn
  end

  def name = NAME

  def parameters_schema
    schema = {
      "type" => "object",
      "properties" => {
        RUNBOOK_ARG => { "type" => "string", "description" => "The runbook's name, slug or another name it goes by" },
        INPUTS_ARG => { "type" => "object", "description" => "A value for each of the runbook's inputs by its key, such as {\"bump\": \"patch\"} (optional for one with a default)" }
      },
      "required" => [ RUNBOOK_ARG ]
    }
    requires_approval? ? Chat::Tools.with_intent(schema) : schema
  end

  # A run changes things in several places at once, so the person confirms it first, unless they allowed runbooks for
  # the rest of this chat. A request that would be refused anyway is let through at once, so the refusal reaches Halon
  # and nobody is asked about a run that cannot start.
  def requires_approval? = @turn.asker.present? && !@turn.chat&.allows_tool?(NAME)

  def approval_resolver = Chat::Tools::Target.resolver(@turn) { |given| refusal_before_running(given).present? }

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    refused = refusal_before_running(given)
    return refused(tool_call, refused) if refused

    runbook = find(given)
    values = runbook.resolve_inputs(given[INPUTS_ARG]).values
    Run.new(@turn, runbook, values).call.tap { |run| Chat::Tools.mark_failed(@turn, tool_call&.id) if run.stopped? }.said
  end

  # What the confirmation shows under the question: each step's tool with the arguments it will be called with, and what
  # is watched after, so the person confirms the run itself rather than Halon's words about it.
  def self.plan_rows(workspace, arguments)
    given = arguments.to_h.stringify_keys
    runbook = Runbook.named(workspace.runbooks.active, given[RUNBOOK_ARG])
    return [] unless runbook&.procedure?

    values = runbook.resolve_inputs(given[INPUTS_ARG]).values
    steps = runbook.runbook_steps.map do |step|
      planned = step.tool? ? "#{step.tool} #{Runbook.filled(step.arguments, values).to_json}" : BY_HAND
      [ "Step #{step.position}: #{step.title}", planned.truncate(Chat::Tools::ASKED_LIMIT) ]
    end
    watch = runbook.filled_watch(values)
    steps + (watch ? [ [ "Then watch", watched(watch) ] ] : [])
  end

  def self.watched(watch)
    labels = Array(watch["steps"]).filter_map { |step| step["label"].presence || step["resource"] }
    [ watch["title"].presence, labels.to_sentence.presence ].compact.join(": ")
  end

  private

  def find(given) = Runbook.named(@turn.workspace.runbooks.active.includes(:runbook_steps), given[RUNBOOK_ARG])

  # Everything that would stop the run before any step, in words Halon can act on.
  def refusal_before_running(given)
    return "Say which runbook, by its name." if given[RUNBOOK_ARG].to_s.strip.empty?
    return "#{@turn.asker_name} may not read runbooks, so none can be run." unless reads_runbooks?

    runbook = find(given)
    return "No runbook is called #{given[RUNBOOK_ARG]}. search_runbooks lists them." unless runbook
    return "#{runbook.name} has no step for Halon to run, so a person follows it by hand. get_runbook shows its steps." unless runbook.procedure?

    missing = runbook.resolve_inputs(given[INPUTS_ARG]).missing
    "Ask the person first: #{missing.map { |input| input['question'] }.join(' ')} Then call it again with #{INPUTS_ARG}." if missing.any?
  end

  def reads_runbooks?
    action = Ability::Action.lookup(Ability::Action.system_key(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ), @turn.workspace)
    @turn.asker.present? && @turn.asker.permitted_to?(action, @turn.workspace)
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    text
  end

  # One run of the steps, in order, stopping at the first that does not go through.
  class Run
    def initialize(turn, runbook, values)
      @turn = Recording.new(turn)
      @runbook = runbook
      @values = values
      @lines = []
      @stopped = false
    end

    def stopped? = @stopped

    def said = @lines.join("\n")

    def call
      tools = Chat::Tools.catalog(@turn).index_by { |entry| entry.name.to_s }
      @runbook.runbook_steps.each do |step|
        next @lines << "Step #{step.position} (#{step.title}) is left to the person, so Halon did not run it." unless step.tool?
        break unless run_step(step, step.position, tools[step.tool])
      end
      return self if @stopped

      @lines << "Every step of #{@runbook.name} went through."
      watch = @runbook.filled_watch(@values)
      @lines << Conversation::Watches.start(@turn.__getobj__, watch) if watch
      self
    end

    private

    def run_step(step, number, entry)
      named = "Step #{number} (#{step.title})"
      return stop("#{named} was not run: #{unavailable(step, entry)}") unless entry&.tool

      arguments = Runbook.filled(step.arguments, @values)
      unfilled = Runbook.placeholders_in(arguments)
      return stop("#{named} was not run: it uses #{unfilled.map { |key| "{{#{key}}}" }.to_sentence}, which the runbook no longer asks for.") if unfilled.any?

      @turn.reset!
      answer = entry.tool.call(**arguments.deep_symbolize_keys)
      return stop("#{named} is waiting for an approval, so the run stopped there. #{answer}") if @turn.held? || waiting?(entry)
      return stop("#{named} failed, so the run stopped there. #{answer.to_s.truncate(ANSWER_LIMIT)}") if @turn.failed?

      @lines << "#{named} went through. It answered: #{answer.to_s.truncate(ANSWER_LIMIT)}"
      true
    end

    def waiting?(entry) = entry.tool.respond_to?(:waiting?) && entry.tool.waiting?

    def unavailable(step, entry)
      return "there is no tool called #{step.tool} here, so the runbook needs updating or the tool switching on." unless entry

      need = entry.description.to_s[/\ANeeds the .+? pack[^.]*\./]
      "#{@turn.asker_name} may not use #{step.tool}.#{" #{need}" if need}"
    end

    def stop(text)
      @stopped = true
      @lines << text
      false
    end
  end

  # The turn each step runs on, noting whether the step was refused, failed or held for an approval, which every tool a
  # chat offers reports through Chat::Tools.mark_failed and Turn#hold!.
  class Recording < SimpleDelegator
    def reset!
      @failed = false
      @held = false
    end

    def failed? = @failed == true

    def held? = @held == true

    def call_failed!(_kind)
      @failed = true
    end

    def hold!(...)
      @held = true
      __getobj__.hold!(...)
    end
  end
end
