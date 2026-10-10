# Halon's terminal runs one shell command in the sandbox the run reads code in, which starts the first time a run needs it.
# A large saved result can be placed there as a file first, so a script filters, counts or groups it and only the
# answer comes back. ff, and a provider's own command line tool, call the workspace's connected tools through Firefight
# (Chat::Terminal::Relay). Running the command is open and ledgered, and each call it makes is authorized as its own
# tool. A command that changes something says so with changes, and the person confirms it before it runs, as any change.
class Chat::Tools::Terminal < RubyLLM::Tool
  NAME = "run_command".freeze
  ACTION = Ability::Action::SANDBOX_COMMAND
  COMMAND_ARG = "command".freeze
  RESULTS_ARG = "results".freeze
  CHANGES_ARG = "changes".freeze
  TIMEOUT_ARG = "timeout_seconds".freeze
  DEFAULT_TIMEOUT = 120
  MAX_TIMEOUT = 15 * 60
  # Enough of what a command printed for the model to read, a larger output is saved like any large result.
  OUTPUT_LIMIT = 200_000
  TOKEN_SHOWN = "[REDACTED:terminal_token]".freeze

  # Not offered where this install has no sandbox.
  def self.all(agent_run) = Integrations::Terminal.available?(agent_run.workspace) ? [ new(agent_run) ] : []

  def self.tool_name = NAME

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = NAME

  def description
    [
      "Run one shell command (bash) in a Linux sandbox of this #{@agent_run.reads_only? ? 'run' : 'chat'}, in a folder of its own. " \
      "Use it to filter, count, group or compare data with a script (python3, ruby, jq, awk, sqlite3 are there), " \
      "for a check only a command can make, and to call connected tools in a loop. Pass saved results such as result_2 in " \
      "#{RESULTS_ARG} and each is placed as a file, results/result_2.txt, so a script reads it whole and you read only the answer.",
      "In a script, ff calls any connected tool you can call, through Firefight, which adds the keys and records each call: " \
      "ff tools lists them, ff help <tool> shows a tool's arguments, ff <tool> key=value calls one and prints its answer.",
      changes_sentence,
      clis_sentence,
      "No key or password is in the sandbox, so never put one in a command. The sandbox starts the first time it is needed " \
      "and stays for the rest of this #{@agent_run.reads_only? ? 'run' : 'chat'} while it is used."
    ].compact.join(" ")
  end

  def parameters_schema
    properties = {
      COMMAND_ARG => { "type" => "string", "description" => "The command, such as jq '.[] | .status' results/result_2.txt | sort | uniq -c" },
      RESULTS_ARG => { "type" => "array", "items" => { "type" => "string" },
                       "description" => "Saved results to place as files first, by name, such as [\"result_2\"] (optional)" },
      TIMEOUT_ARG => { "type" => "integer", "description" => "At most this many seconds (optional, #{DEFAULT_TIMEOUT}, at most #{MAX_TIMEOUT})" }
    }
    unless @agent_run.reads_only?
      properties[CHANGES_ARG] = { "type" => "boolean", "description" => "True when the command changes something through a connected tool, " \
                                                                       "so the person confirms it first (optional, false)" }
      properties[Chat::Tools::INTENT_ARG] = Chat::Tools::INTENT.merge("description" => "#{Chat::Tools::INTENT['description']}. Needed when changes is true")
    end
    { "type" => "object", "properties" => properties, "required" => [ COMMAND_ARG ] }
  end

  # A command that changes something is confirmed like any change, unless the person allowed commands for this chat. One
  # that only reads is let through at once, and so is one that would be refused anyway.
  def requires_approval? = !@agent_run.reads_only? && @agent_run.acting_principal.present? && !@agent_run.chat&.allows_tool?(NAME)

  def approval_resolver = Chat::Tools::Target.resolver(@agent_run) { |given| !changes?(given) || refusal(given).present? }

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    refused = refusal(given)
    return failed(tool_call, refused) if refused

    command = given[COMMAND_ARG].to_s
    params = { COMMAND_ARG => command, RESULTS_ARG => handles(given).presence, CHANGES_ARG => (true if changes?(given)) }.compact
    said = @agent_run.tool_call(action_key: ACTION, params: params, tool_name: NAME, label: "Run #{command.truncate(80)}") { run(given, command) }
    Chat::Tools.hand_over(@agent_run, NAME, said)
  rescue Integrations::Error => error
    failed(tool_call, FirefightAi::Evidence.frame(NAME, "The command did not run: #{error.message}"))
  end

  private

  def run(given, command)
    terminal = Integrations::Terminal.new(key: @agent_run.code_box_key, workspace: @agent_run.workspace)
    placed = saved(given).map { |result| terminal.place("#{result.handle}.txt", result.content) }
    session, token = Chat::TerminalSession.open!(@agent_run, changes: changes?(given), lasts: timeout(given).seconds)
    begin
      env = Chat::Terminal.env(session, token)
      said = terminal.run(command, env: env, timeout: timeout(given))
    ensure
      session.finish!
    end
    shown(without_token(said, token), placed, reached: env.key?(Chat::Terminal::URL_VARIABLE))
  end

  # The token is dead once the command ends, and still never reaches the chat, should a command print it.
  def without_token(said, token)
    said.to_h.transform_values { |value| value.is_a?(String) ? value.gsub(token, TOKEN_SHOWN) : value }
  end

  def shown(said, placed, reached:)
    lines = []
    lines << "Placed #{placed.to_sentence}." if placed.any?
    lines << Chat::Terminal::NO_ADDRESS unless reached
    lines << exit_line(said)
    lines << "stdout:\n#{said['stdout'].to_s.truncate(OUTPUT_LIMIT)}" if said["stdout"].present?
    lines << "stderr:\n#{said['stderr'].to_s.truncate(OUTPUT_LIMIT)}" if said["stderr"].present?
    lines << "The output passed 10 MB, so the rest was cut. Print less, such as a count or a summary." if said["truncated"]
    lines.join("\n")
  end

  def exit_line(said)
    return "Stopped after the time limit, so it did not finish. Give it longer with #{TIMEOUT_ARG}, or do less at once." if said["timed_out"]

    "Exit code #{said['exit_code'].inspect}#{'. No output' if said['stdout'].blank? && said['stderr'].blank?}."
  end

  def refusal(given)
    return "Give the command to run." if given[COMMAND_ARG].to_s.strip.empty?
    return "This #{run_word} only reads, so a command that changes something is not run here. A change belongs in the fix." if changes?(given) && @agent_run.reads_only?

    missing = handles(given) - saved(given).map(&:handle)
    "Nothing is saved as #{missing.to_sentence}. read_result with no result named lists what is saved." if missing.any?
  end

  def run_word = @agent_run.chat_owner.is_a?(Investigation) ? "investigation" : "run"

  def changes?(given) = ActiveModel::Type::Boolean.new.cast(given[CHANGES_ARG]) == true

  def handles(given) = Array(given[RESULTS_ARG]).map { |handle| handle.to_s.strip }.compact_blank.uniq

  def saved(given)
    wanted = handles(given)
    return [] if wanted.empty?

    @agent_run.chat&.saved_results.to_a.select { |result| wanted.include?(result.handle) }
  end

  def timeout(given)
    asked = given[TIMEOUT_ARG].to_i
    asked.positive? ? [ asked, MAX_TIMEOUT ].min : DEFAULT_TIMEOUT
  end

  def changes_sentence
    return "This #{run_word} only reads, so a command that changes something through a connected tool is refused." if @agent_run.reads_only?

    "A command that changes something through a connected tool needs #{CHANGES_ARG} true and an intent, and the person confirms " \
      "it first. Without it, every call it makes that changes something is refused."
  end

  # Read once, since the description is read on every turn and listing the tools reads the workspace's grants.
  def clis_sentence
    @clis_sentence = Chat::Terminal.clis_sentence(@agent_run) unless defined?(@clis_sentence)
    @clis_sentence
  end

  def failed(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end
