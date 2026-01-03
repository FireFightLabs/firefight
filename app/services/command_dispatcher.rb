# Routes commands to appropriate handlers based on command text
# Platform-agnostic - works with any Command object
class CommandDispatcher
  class UnknownCommandError < StandardError; end

  # Find the appropriate handler for a command
  #
  # @param command [Command] Platform-agnostic command object
  # @return [Class] Handler class to execute
  def self.find(command)
    # If command is blank (no text), open modal
    return Commands::ModalHandler if command.blank?

    # Parse subcommand (first word)
    case command.subcommand&.downcase
    when "help", "h", "?"
      Commands::HelpHandler
    when "status", "s"
      Commands::StatusHandler
    when "list", "ls"
      Commands::ListHandler
    else
      # Default: open modal for any unknown command
      Commands::ModalHandler
    end
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
