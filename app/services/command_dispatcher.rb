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
    handler.execute(command)
  end
end
