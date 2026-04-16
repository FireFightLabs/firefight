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
    ensure_member_provisioned(command)
    handler = find(command)
    handler.execute(command)
  end

  # Auto-provision a WorkspaceMembership for the user invoking the command.
  # Mirrors the InteractionDispatcher behaviour. Failures are logged but never
  # block the slash command from running.
  def self.ensure_member_provisioned(command)
    workspace = command.workspace
    return unless workspace

    WorkspaceMemberProvisioner.find_or_provision!(
      workspace: workspace,
      platform_user_id: command.user_id,
      adapter: workspace.adapter
    )
  rescue StandardError => e
    Rails.logger.warn({
      event: "command_dispatcher.provisioning_failed",
      user_id: command.user_id,
      error: e.message
    })
  end
  private_class_method :ensure_member_provisioned
end
