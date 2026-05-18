module Commands
  class HomeHandler
    SUBCOMMANDS = Identifiers.constants
      .select { |c| c.to_s.start_with?("SUBCOMMAND_") }
      .map { |c| Identifiers.const_get(c) }
      .freeze

    def self.execute(command)
      subcommand = command.subcommand&.downcase

      case subcommand
      when Identifiers::SUBCOMMAND_NEW
        Commands::ModalHandler.execute(command)
      when Identifiers::SUBCOMMAND_HOME, nil
        Commands::HomeModalHandler.execute(command)
      when Identifiers::SUBCOMMAND_SUMMARY
        Commands::SummaryHandler.execute(command)
      when Identifiers::SUBCOMMAND_LEAD
        Commands::LeadHandler.execute(command)
      when Identifiers::SUBCOMMAND_STATUS
        Commands::StatusHandler.execute(command)
      when Identifiers::SUBCOMMAND_UPDATE
        Commands::UpdateHandler.execute(command)
      when Identifiers::SUBCOMMAND_SEVERITY
        Commands::SeverityHandler.execute(command)
      when Identifiers::SUBCOMMAND_ESCALATE
        Commands::EscalateHandler.execute(command)
      when Identifiers::SUBCOMMAND_INVITE
        Commands::InviteHandler.execute(command)
      when Identifiers::SUBCOMMAND_ACTION, Identifiers::SUBCOMMAND_ACTIONS
        Commands::ActionsHandler.execute(command)
      when Identifiers::SUBCOMMAND_FOLLOWUP, Identifiers::SUBCOMMAND_FOLLOWUPS
        Commands::FollowupsHandler.execute(command)
      when Identifiers::SUBCOMMAND_LINK, Identifiers::SUBCOMMAND_RELATE, Identifiers::SUBCOMMAND_DUPLICATE
        Commands::LinkHandler.execute(command)
      when Identifiers::SUBCOMMAND_CLOSE, Identifiers::SUBCOMMAND_RESOLVE
        Commands::CloseHandler.execute(command)
      when Identifiers::SUBCOMMAND_REOPEN
        Commands::ReopenHandler.execute(command)
      when Identifiers::SUBCOMMAND_POSTMORTEM
        Commands::PostmortemHandler.execute(command)
      when Identifiers::SUBCOMMAND_CATCHUP
        Commands::CatchupHandler.execute(command)
      when Identifiers::SUBCOMMAND_TIMELINE
        Commands::TimelineHandler.execute(command)
      when Identifiers::SUBCOMMAND_LIST
        Commands::ListHandler.execute(command)
      when Identifiers::SUBCOMMAND_SHOUTOUT
        Commands::ShoutoutHandler.execute(command)
      else
        suggestion = suggest_subcommand(subcommand)
        msg = if suggestion
          "Unknown subcommand `#{subcommand}`. Did you mean `#{suggestion}`?"
        else
          "Unknown subcommand `#{subcommand}`. Type `/ff` for available commands."
        end
        Command.ephemeral(msg)
      end
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

    private_class_method def self.suggest_subcommand(input)
      checker = DidYouMean::SpellChecker.new(dictionary: SUBCOMMANDS)
      checker.correct(input).first
    end
  end
end
