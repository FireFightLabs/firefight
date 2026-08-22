class CommandDispatcher
  class UnknownCommandError < StandardError; end

  COMMAND_HANDLERS = {
    "firefight" => Commands::HomeHandler,
    "ff" => Commands::HomeHandler
  }.freeze

  def self.find(command)
    handler = COMMAND_HANDLERS[command.command_name]
    return handler if handler

    Commands::DeclareIncident
  end

  # /ff routes through HomeHandler, so the authorization to check belongs to
  # the command the subcommand names, not to the sub-dispatcher in front of it.
  def self.authorizing_handler(command)
    handler = find(command)
    return handler unless handler.respond_to?(:handler_for)

    handler.handler_for(command.subcommand) || handler
  end

  def self.dispatch(command)
    handler = find(command)
    OpenTelemetry::Trace.current_span.add_attributes({
      "slack.command_name" => command.command_name,
      "slack.subcommand" => command.subcommand,
      "slack.handler" => handler.name
    }.compact)

    AuthorizedDispatch.call(authorizing_handler(command), command, context: { incident_id: command.incident&.id }) do
      handler.execute(command)
    end
  rescue AuthorizedDispatch::PrincipalUnresolved
    Command.ephemeral(AuthorizedDispatch::UNRESOLVED_MESSAGE)
  rescue AbilityGateway::Denied => e
    Command.ephemeral(AuthorizedDispatch.denied_message(e))
  rescue AbilityGateway::PendingApproval => e
    ApprovalResumption.park!(e.approval, command, ApprovalResumption::KIND_COMMAND)
    Command.ephemeral(AuthorizedDispatch.pending_message(e.approval))
  rescue Incident::NotActive => e
    Command.ephemeral(e.message)
  end
end
