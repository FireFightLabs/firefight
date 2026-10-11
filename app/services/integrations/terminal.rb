module Integrations
  # Halon's terminal, in the same box a run reads code in (CodeReading). The box starts the first time a run needs it and
  # stops as code reading's box does, when the run ends or the box sits idle, so a run that never runs a command never
  # starts one. What a command reaches of the workspace's systems it reaches through Firefight (Chat::TerminalSession),
  # never with a key of its own.
  class Terminal
    # Where the image keeps the check of an address from outside (sandbox/outside_check.rb).
    OUTSIDE_CHECK = "/opt/sandbox/outside_check.rb".freeze
    OUTSIDE_CHECK_TIMEOUT = 90
    # How long a browser check (sandbox/browser_check.mjs) may take, which the box runs as a user of its own.
    BROWSER_DEADLINE_SECONDS = 120
    BROWSER_MAX_DEADLINE = 170
    # The script answers by its own deadline, and this is how much longer the app waits for that answer.
    BROWSER_MARGIN = 10
    # Private addresses the browser may still reach, named by an operator as for any connection to a private host.
    BROWSER_PRIVATE_HOSTS = PublicAddress.allowed_env(:browser)
    # A file the app places for a command sits here, by the name it is given.
    FILES = "/terminal/results".freeze
    SHELL = [ "bash", "-c" ].freeze

    # Whether a box can be started for the workspace at all. Without one the terminal is not offered.
    def self.available?(workspace) = SandboxProviders.order_for(workspace).any?

    # What the box sees an address as from outside, as sandbox/outside_check.rb answers it, and the region of the box
    # it ran in, nil when its provider does not say.
    Checked = Data.define(:answer, :region)

    def initialize(key:, workspace:)
      @reading = CodeReading.new(key: key, workspace: workspace)
    end

    # One shell command in the terminal's folder, as the terminal's own user. env carries how it reaches Firefight.
    def run(command, env: {}, timeout: 60)
      @reading.terminal(argv: [ *SHELL, command.to_s ], env: env, timeout: timeout, on_output: ->(_said) { })
    end

    # Places text as a file a command reads, answering where it is.
    def place(name, content)
      @reading.place_file(name, content)
      "#{FILES}/#{name}"
    end

    # What a page looks like in a real browser, as sandbox/browser_check.mjs answers it, and the region of the box.
    Browsed = Data.define(:answer, :region)

    # The check runs as an argument list, never through a shell, so an address cannot become a command.
    def check(url, method:)
      said = @reading.terminal(argv: [ "ruby", OUTSIDE_CHECK, url.to_s, method.to_s ], timeout: OUTSIDE_CHECK_TIMEOUT)
      answer = JSON.parse(said["stdout"].to_s.lines.last.to_s)
      Checked.new(answer: answer, region: Sandboxes.region(@reading.box_provider_key))
    rescue JSON::ParserError
      raise Error, "The check from the sandbox answered with something that is not JSON: #{said['stderr'].to_s.strip.lines.last}"
    end

    # Opens a page in the box's browser. The spec is handed over as the check's input, never in argv, the environment or a
    # file, since it may carry a saved login's password for this one run. Which private hosts it may reach is the operator's
    # word alone, so a caller's is replaced.
    def browse(spec)
      given = spec.to_h.stringify_keys
      deadline = (given["deadline_seconds"].presence || BROWSER_DEADLINE_SECONDS).to_i.clamp(1, BROWSER_MAX_DEADLINE)
      given = given.merge("deadline_seconds" => deadline, "private_hosts" => ENV.fetch(BROWSER_PRIVATE_HOSTS, "").split(",").map(&:strip).compact_blank)
      said = @reading.browse(spec: given.to_json, timeout: deadline + BROWSER_MARGIN)
      Browsed.new(answer: JSON.parse(said["stdout"].to_s.lines.last.to_s), region: Sandboxes.region(@reading.box_provider_key))
    rescue JSON::ParserError
      raise Error, "The browser in the sandbox answered with something that is not JSON: #{said['stderr'].to_s.strip.lines.last}"
    end
  end
end
