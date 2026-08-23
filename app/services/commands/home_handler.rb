module Commands
  # Sub-dispatcher for /ff. Routes a subcommand to the command that owns it.
  # The table is also what CommandDispatcher reads to find the leaf whose
  # authorization the Ability Gateway checks, so routing has one source.
  class HomeHandler
    extend HandlerAuthorization
    # Only reached directly for a subcommand nothing owns, which just prints
    # a suggestion.
    authorizes_nothing

    SUBCOMMAND_HANDLERS = {
      Identifiers::SUBCOMMAND_NEW => Commands::DeclareIncident,
      Identifiers::SUBCOMMAND_HOME => Commands::OpenHome,
      Identifiers::SUBCOMMAND_SUMMARY => Commands::UpdateSummary,
      Identifiers::SUBCOMMAND_LEAD => Commands::AssignLead,
      Identifiers::SUBCOMMAND_ROLE => Commands::AssignRoles,
      Identifiers::SUBCOMMAND_ROLES => Commands::AssignRoles,
      Identifiers::SUBCOMMAND_STATUS => Commands::ChangeStatus,
      Identifiers::SUBCOMMAND_UPDATE => Commands::UpdateIncident,
      Identifiers::SUBCOMMAND_SEVERITY => Commands::ChangeSeverity,
      Identifiers::SUBCOMMAND_ESCALATE => Commands::EscalateIncident,
      Identifiers::SUBCOMMAND_INVITE => Commands::InviteResponders,
      Identifiers::SUBCOMMAND_ACTION => Commands::ListActions,
      Identifiers::SUBCOMMAND_ACTIONS => Commands::ListActions,
      Identifiers::SUBCOMMAND_FOLLOWUP => Commands::ListFollowups,
      Identifiers::SUBCOMMAND_FOLLOWUPS => Commands::ListFollowups,
      Identifiers::SUBCOMMAND_LINK => Commands::LinkIncident,
      Identifiers::SUBCOMMAND_RELATE => Commands::LinkIncident,
      Identifiers::SUBCOMMAND_DUPLICATE => Commands::LinkIncident,
      Identifiers::SUBCOMMAND_CLOSE => Commands::CloseIncident,
      Identifiers::SUBCOMMAND_RESOLVE => Commands::CloseIncident,
      Identifiers::SUBCOMMAND_CANCEL => Commands::CancelIncident,
      Identifiers::SUBCOMMAND_REOPEN => Commands::ReopenIncident,
      Identifiers::SUBCOMMAND_OPEN => Commands::ReopenIncident,
      Identifiers::SUBCOMMAND_POSTMORTEM => Commands::GeneratePostmortem,
      Identifiers::SUBCOMMAND_CATCHUP => Commands::GenerateCatchup,
      Identifiers::SUBCOMMAND_TIMELINE => Commands::ShowTimeline,
      Identifiers::SUBCOMMAND_LIST => Commands::ListActiveIncidents,
      Identifiers::SUBCOMMAND_SHOUTOUT => Commands::GiveShoutout,
      Identifiers::SUBCOMMAND_RUNBOOK => Commands::AttachRunbook,
      Identifiers::SUBCOMMAND_RUNBOOKS => Commands::AttachRunbook
    }.freeze

    SUBCOMMANDS = SUBCOMMAND_HANDLERS.keys.freeze

    # Bare /ff opens the home modal, same as `/ff home`.
    def self.handler_for(subcommand)
      return Commands::OpenHome if subcommand.blank?

      SUBCOMMAND_HANDLERS[subcommand.downcase]
    end

    def self.execute(command)
      subcommand = command.subcommand&.downcase
      handler = handler_for(subcommand)
      return handler.execute(command) if handler

      Command.ephemeral(unknown_message(subcommand))
    rescue => e
      Rails.logger.error({
        event: "firefight.command_error",
        command: command.text,
        subcommand: subcommand,
        error: e.message,
        backtrace: e.backtrace&.first(5)
      }.to_json)

      Command.ephemeral("Sorry, something went wrong. Please try again.")
    end

    private_class_method def self.unknown_message(subcommand)
      suggestion = suggest_subcommand(subcommand)
      return "Unknown subcommand `#{subcommand}`. Did you mean `#{suggestion}`?" if suggestion

      "Unknown subcommand `#{subcommand}`. Type `/ff` for available commands."
    end

    private_class_method def self.suggest_subcommand(input)
      checker = DidYouMean::SpellChecker.new(dictionary: SUBCOMMANDS)
      checker.correct(input).first
    end
  end
end
