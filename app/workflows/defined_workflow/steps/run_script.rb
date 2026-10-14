# A Python, Ruby or JavaScript script kept in the step, run in the run's sandbox with the step's data on its input and in
# $STEP_DATA, and what it prints read back as JSON. It only reads unless the step says it changes something, as a
# command's does.
class DefinedWorkflow::Steps::RunScript < DefinedWorkflow::Steps::Sandbox
  kind "run_script"
  label "Run script"
  group GROUP_SANDBOX

  KEY_LANGUAGE = "language".freeze
  KEY_SCRIPT = "script".freeze
  LANGUAGE_PYTHON = "python".freeze
  LANGUAGE_RUBY = "ruby".freeze
  LANGUAGE_JAVASCRIPT = "javascript".freeze
  # How each language's script is kept in the box and run there, by the image's own runtimes.
  RUNNERS = {
    LANGUAGE_PYTHON => [ "script.py", "python3" ], LANGUAGE_RUBY => [ "script.rb", "ruby" ], LANGUAGE_JAVASCRIPT => [ "script.mjs", "node" ]
  }.freeze
  LANGUAGES = RUNNERS.keys.freeze
  SCRIPT_LIMIT = 50_000
  OUTPUT_RESULT = "result".freeze
  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_STDOUT = DefinedWorkflow::Steps::Sandbox::OUTPUT_STDOUT
  OUTPUT_STDERR = DefinedWorkflow::Steps::Sandbox::OUTPUT_STDERR

  config_help "language (#{LANGUAGES.join(', ')}), script (the code, reading the step's data as JSON on its input or from the file " \
              "$STEP_DATA, printing JSON), data (what it is given, usually a reference), changes (true when it changes something, which needs " \
              "undo), timeout_seconds (1 to 900). Outputs result (what it printed, read as JSON), stdout and stderr."

  class << self
    def output_fields(_config) = [ OUTPUT_RESULT, OUTPUT_STDOUT, OUTPUT_STDERR ]

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = sandbox_problems(config, named, workspace)
      found << "#{named} runs #{LANGUAGES.to_sentence(last_word_connector: ' or ')}." unless LANGUAGES.include?(config[KEY_LANGUAGE].to_s)
      found << "#{named} needs its script." if config[KEY_SCRIPT].to_s.strip.empty?
      found << "#{named} keeps a script of at most #{SCRIPT_LIMIT.to_fs(:delimited)} characters." if config[KEY_SCRIPT].to_s.length > SCRIPT_LIMIT
      found + undo_problems(step, workspace)
    end

    def describe(config, _workspace) = "#{config[KEY_LANGUAGE].to_s.capitalize} script: #{config[KEY_SCRIPT].to_s.lines.first.to_s.strip}".truncate(200)
  end

  def perform
    stopped = before_a_change(@step.label)
    return stopped if stopped
    raise Refused, UNAVAILABLE unless Integrations::Terminal.available?(workspace)

    file, runtime = RUNNERS.fetch(@config[KEY_LANGUAGE].to_s) { raise Refused, "#{@step.label} runs #{LANGUAGES.to_sentence(last_word_connector: ' or ')}." }
    said = in_sandbox do
      script = terminal.place(file, @config[KEY_SCRIPT].to_s)
      data = place_data || terminal.place(DATA_FILE, "null")
      run_command("#{runtime} #{script} < #{data}", label: "The script", params: { KEY_LANGUAGE => @config[KEY_LANGUAGE].to_s })
    end
    result = said[OUTPUT_DATA]
    raise Failed, "The script printed nothing that reads as JSON. Print one JSON object or list, last." if result.nil? && said[OUTPUT_STDOUT].strip.present?

    { OUTPUT_RESULT => result, OUTPUT_STDOUT => said[OUTPUT_STDOUT], OUTPUT_STDERR => said[OUTPUT_STDERR] }
  end
end
