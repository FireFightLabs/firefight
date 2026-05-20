class CommandDispatcher
  class UnknownCommandError < StandardError; end

  COMMAND_HANDLERS = {
    "firefight" => Commands::HomeHandler,
    "ff" => Commands::HomeHandler
  }.freeze

  def self.find(command)
    handler = COMMAND_HANDLERS[command.command_name]
    return handler if handler

    Commands::ModalHandler
  end

  def self.dispatch(command)
    handler = find(command)
    OpenTelemetry::Trace.current_span.add_attributes({
      "slack.command_name" => command.command_name,
      "slack.subcommand" => command.subcommand,
      "slack.handler" => handler.name
    }.compact)
    handler.execute(command)
  end
end
