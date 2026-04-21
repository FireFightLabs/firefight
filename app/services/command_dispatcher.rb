# Routes commands to appropriate handlers based on slash command name
# Platform-agnostic - works with any Command object
class CommandDispatcher
  class UnknownCommandError < StandardError; end

  COMMAND_HANDLERS = {
    "firefight" => Commands::Firefight::HomeHandler,
    "ff" => Commands::Firefight::HomeHandler
  }.freeze

  # Find the appropriate handler for a command
  #
  # @param command [Command] Platform-agnostic command object
  # @return [Class] Handler class to execute
  def self.find(command)
    # Route by slash command name (e.g., /firefight, /ff)
    handler = COMMAND_HANDLERS[command.command_name]
    return handler if handler

    # Fallback: open modal for unrecognized commands
    Commands::ModalHandler
  end

  # Execute the appropriate handler for a command
  #
  # @param command [Command] Platform-agnostic command object
  # @return [void]
  def self.dispatch(command)
    handler = find(command)
    handler.execute(command)
  end
end
