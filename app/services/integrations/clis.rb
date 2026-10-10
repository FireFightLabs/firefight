module Integrations
  # A provider's own command line tool in Halon's terminal, pointed at Firefight instead of the provider. The box hands it
  # the command's token in place of a key, and every request it makes arrives at Firefight's relay, which turns it into a
  # call of one of the connection's own tools, so permissions, approval rules, the read contract and the activity log
  # apply to it exactly as to Halon's own call, and Firefight adds the key. A provider's definition names its cli, a
  # module answering:
  #
  #   COMMAND                               the command in the box, such as northflank
  #   TOOL                                  the connection tool every request runs as, which takes any call to its API
  #   env(base_url, token)                  what the command is handed so it reaches base_url with token
  #   arguments(verb, path, query, body)    the tool's arguments for one request, or raises Refused saying what it cannot reach
  #   answer(relayed)                       the body the command reads back, from the API's own answer (Telemetry::RELAYED)
  module Clis
    class Refused < Integrations::Error; end

    # A connection's command line tool, as the terminal hands it out.
    Offered = Data.define(:connection, :name, :command, :env)

    def self.for(integration) = Provider.for(integration.provider).cli

    # Each connection in tools whose provider has a command line tool and whose relayed tool is among them. base_url is
    # the relay's address, under which each connection has its own.
    def self.offered(tools, base_url:, token:)
      tools.group_by(&:integration).filter_map do |integration, held|
        cli = self.for(integration)
        next unless cli && held.any? { |tool| tool.name == cli::TOOL }

        Offered.new(connection: integration.slug, name: integration.display_name, command: cli::COMMAND,
                    env: cli.env("#{base_url}/#{integration.slug}", token))
      end
    end
  end
end
