# What the steps that run in the sandbox share: one box per run (Workflow::Run#code_box_key), started the first time a
# step needs it and stopped when the run ends, step data placed in it as a file, never a key, and every command's call
# through the gateway as whoever the run acts as. A command reaches the workspace's connected tools only through
# Firefight (ff, Chat::TerminalSession), and a change through them only when its step says it changes something.
class DefinedWorkflow::Steps::Sandbox < DefinedWorkflow::Steps::Base
  KEY_DATA = "data".freeze
  KEY_CHANGES = "changes".freeze
  KEY_TIMEOUT = "timeout_seconds".freeze
  # Where a step's data is placed for its command, and the variable naming it.
  DATA_FILE = "step_data.json".freeze
  DATA_VARIABLE = "STEP_DATA".freeze
  OUTPUT_EXIT_CODE = "exit_code".freeze
  OUTPUT_STDOUT = "stdout".freeze
  OUTPUT_STDERR = "stderr".freeze
  OUTPUT_DATA = "data".freeze
  TIMEOUTS = (1..900)
  DEFAULT_TIMEOUT = 120
  # What a step keeps of what a command printed. Anything longer is cut, saying so.
  PRINTED_LIMIT = 100_000
  UNAVAILABLE = "No sandbox can be started for this workspace, so this step cannot run.".freeze
  NO_ADDRESS = Chat::Terminal::NO_ADDRESS

  class << self
    # A command that says it changes something is a change: its step needs its undo and a check after it, a test run
    # only shows it, and the read before a change nobody pressed, approval rules and freeze windows apply.
    def changes?(config, _workspace) = ActiveModel::Type::Boolean.new.cast(config[KEY_CHANGES]) == true

    def checks?(config, workspace) = !changes?(config, workspace)

    def output_fields(_config) = [ OUTPUT_EXIT_CODE, OUTPUT_STDOUT, OUTPUT_STDERR, OUTPUT_DATA ]

    def sandbox_problems(config, named, workspace)
      found = []
      found << "#{named} needs a sandbox, and none can be started for this workspace." unless Integrations::Terminal.available?(workspace)
      timeout = config[KEY_TIMEOUT]
      if timeout.present? && !(timeout.to_s.match?(/\A\d+\z/) && TIMEOUTS.cover?(timeout.to_i))
        found << "#{named} runs for #{TIMEOUTS.first} to #{TIMEOUTS.last} seconds."
      end
      found
    end

    # A command is open to everyone, so it needs no grant. What it reaches through ff is authorized call by call.
    def reach(_config, _workspace) = []
  end

  private

  def terminal = @terminal ||= Integrations::Terminal.new(key: @run.code_box_key, workspace: workspace)

  def timeout = (@config[KEY_TIMEOUT].presence || DEFAULT_TIMEOUT).to_i.clamp(TIMEOUTS.first, TIMEOUTS.last)

  # A change is pretended in a test run, and waits out or stops for a freeze, and reads how things stand first when
  # nobody pressed Run, as any change does. Answers a park, a pretended output, or nil to go on.
  def before_a_change(named)
    return simulated_output(self.class.describe(@config, workspace)) if simulated?
    return unless changes?

    parked = frozen
    return parked if parked

    first = read_first(named, [ [ "command", self.class.describe(@config, workspace) ] ])
    first.is_a?(SolidWorkflow::Park) ? first : nil
  end

  # One shell command in the run's box, as whoever the run acts as, with the step's data placed as a file and the relay
  # its calls through Firefight go by. A command that failed or ran out of time fails the step, saying what it printed.
  def run_command(command, label:, params: {})
    raise Refused, UNAVAILABLE unless Integrations::Terminal.available?(workspace)

    agent_run = Workflow::AgentRun.new(run: @run, record: record)
    said = agent_run.tool_call(action_key: Ability::Action::SANDBOX_COMMAND, params: params.merge("changes" => (true if changes?)).compact) do
      placed = place_data
      session, token = Chat::TerminalSession.open!(agent_run, changes: changes?, lasts: timeout.seconds)
      begin
        env = Chat::Terminal.env(session, token).merge(placed ? { DATA_VARIABLE => placed } : {})
        without(terminal.run(command, env: env, timeout: timeout), token)
      ensure
        session.finish!
      end
    end.value
    printed(said, label)
  rescue Integrations::Error => error
    raise Failed, "The sandbox did not run it: #{error.message}"
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(Ability::Action::SANDBOX_COMMAND)
  end

  def place_data
    return if @config[KEY_DATA].nil? || @config[KEY_DATA] == ""

    value = @config[KEY_DATA]
    terminal.place(DATA_FILE, value.is_a?(String) ? value : JSON.pretty_generate(value))
  end

  # The token a command was handed is dead once it ends, and still never kept, should it print it.
  def without(said, token) = said.to_h.transform_values { |value| value.is_a?(String) ? value.gsub(token, "[token]") : value }

  def printed(said, label)
    stdout = said["stdout"].to_s.truncate(PRINTED_LIMIT)
    stderr = said["stderr"].to_s.truncate(PRINTED_LIMIT)
    raise Failed, "#{label} ran past its #{timeout} seconds, so it did not finish." if said["timed_out"]
    raise Failed, "#{label} ended with exit code #{said['exit_code']}. #{stderr.lines.last(3).join.strip.presence || stdout.lines.last(3).join.strip}".strip unless said["exit_code"].to_i.zero?

    { OUTPUT_EXIT_CODE => said["exit_code"].to_i, OUTPUT_STDOUT => stdout, OUTPUT_STDERR => stderr, OUTPUT_DATA => json_in(stdout) }
  end

  # What a command printed read as JSON: the whole of it, else its last line, else nothing.
  def json_in(text)
    [ text, text.lines.last.to_s ].each do |candidate|
      value = JSON.parse(candidate.strip)
      return value if value.is_a?(Hash) || value.is_a?(Array)
    rescue JSON::ParserError
      next
    end
    nil
  end
end
