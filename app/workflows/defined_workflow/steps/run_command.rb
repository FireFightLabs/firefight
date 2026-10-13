# One shell command in the run's sandbox, with the step's data placed as a file ($STEP_DATA) and ff for the workspace's
# connected tools, reached through Firefight. It only reads unless the step says it changes something, which then needs
# its undo and a check after it, and lets its ff calls change things, each through the gateway.
class DefinedWorkflow::Steps::RunCommand < DefinedWorkflow::Steps::Sandbox
  kind "run_command"
  label "Run command"
  group GROUP_SANDBOX
  config_help "command (one shell command, may use references), data (what to place as the file $STEP_DATA, optional), changes (true when it " \
              "changes something, which needs undo), timeout_seconds (1 to 900, 120 by default). Outputs exit_code, stdout, stderr and data " \
              "(what it printed, read as JSON when it is). A command that fails fails the step."

  KEY_COMMAND = "command".freeze
  COMMAND_LIMIT = 10_000

  class << self
    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = sandbox_problems(config, named, workspace)
      found << "#{named} needs the command it runs." if config[KEY_COMMAND].to_s.strip.empty?
      found << "#{named} runs a command of at most #{COMMAND_LIMIT.to_fs(:delimited)} characters." if config[KEY_COMMAND].to_s.length > COMMAND_LIMIT
      found + undo_problems(step, workspace)
    end

    def describe(config, _workspace) = config[KEY_COMMAND].to_s.squish.truncate(200)
  end

  def perform
    stopped = before_a_change(@step.label)
    return stopped if stopped

    run_command(@config[KEY_COMMAND].to_s, label: "The command", params: { KEY_COMMAND => @config[KEY_COMMAND].to_s.truncate(500) })
  end
end
