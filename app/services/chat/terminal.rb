# Halon's terminal from the app's side: what a command is handed so it reaches Firefight, and the relay that takes the
# calls it makes (Relay). The box never holds a provider's key. It holds one token per command (Chat::TerminalSession).
module Chat::Terminal
  # Where the relay answers, under the address the box reaches Firefight at (config/routes.rb).
  RELAY_PATH = "/sandbox_relay".freeze
  # Where a provider's own command line tool reaches the relay, one address per connection below it.
  API_PATH = "api".freeze
  URL_VARIABLE = "FIREFIGHT_RELAY_URL".freeze
  TOKEN_VARIABLE = "FIREFIGHT_RELAY_TOKEN".freeze
  NO_ADDRESS = "Firefight's own address is not set (APP_HOST), so a command cannot reach the connected tools. It still runs.".freeze

  # The address the box reaches Firefight at, the same one a coding agent reaches its model through, or nil when this
  # install has none.
  def self.relay_base
    base = ENV["CODE_AGENT_PROXY_URL"].presence || AppUrl.root
    base && "#{base.to_s.chomp('/')}#{RELAY_PATH}"
  end

  # What a command is handed: the relay and its token, and each provider command line tool pointed at Firefight when one
  # connection has it, so it runs as it is. When several connections have the same one, ff with <connection> picks.
  def self.env(session, token)
    base = relay_base
    return {} unless base

    offered = Relay.new(session).clis(token)
    defaults = offered.group_by(&:command).values.select(&:one?).flatten.map(&:env).reduce({}, :merge)
    defaults.merge(URL_VARIABLE => base, TOKEN_VARIABLE => token)
  end

  # What the tool tells the model about the command line tools it may use, for the run's workspace.
  def self.clis_sentence(agent_run)
    offered = Relay.new(nil, agent_run: agent_run).clis("")
    return if offered.empty?

    listed = offered.map { |cli| "#{cli.command} for #{cli.name} (ff with #{cli.connection} -- #{cli.command} ...)" }
    "Provider command line tools reach their connection through Firefight the same way: #{listed.to_sentence}. " \
      "With one connection for a tool, it runs as it is."
  end
end
