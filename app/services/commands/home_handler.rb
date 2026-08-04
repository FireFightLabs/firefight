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
        Commands::DeclareIncident.execute(command)
      when Identifiers::SUBCOMMAND_HOME, nil
        Commands::OpenHome.execute(command)
      when Identifiers::SUBCOMMAND_SUMMARY
        Commands::UpdateSummary.execute(command)
      when Identifiers::SUBCOMMAND_LEAD
        Commands::AssignLead.execute(command)
      when Identifiers::SUBCOMMAND_ROLE, Identifiers::SUBCOMMAND_ROLES
        Commands::AssignRoles.execute(command)
      when Identifiers::SUBCOMMAND_STATUS
        Commands::ChangeStatus.execute(command)
      when Identifiers::SUBCOMMAND_UPDATE
        Commands::UpdateIncident.execute(command)
      when Identifiers::SUBCOMMAND_SEVERITY
        Commands::ChangeSeverity.execute(command)
      when Identifiers::SUBCOMMAND_ESCALATE
        Commands::EscalateIncident.execute(command)
      when Identifiers::SUBCOMMAND_INVITE
        Commands::InviteResponders.execute(command)
      when Identifiers::SUBCOMMAND_ACTION, Identifiers::SUBCOMMAND_ACTIONS
        Commands::ListActions.execute(command)
      when Identifiers::SUBCOMMAND_FOLLOWUP, Identifiers::SUBCOMMAND_FOLLOWUPS
        Commands::ListFollowups.execute(command)
      when Identifiers::SUBCOMMAND_LINK, Identifiers::SUBCOMMAND_RELATE, Identifiers::SUBCOMMAND_DUPLICATE
        Commands::LinkIncident.execute(command)
      when Identifiers::SUBCOMMAND_CLOSE, Identifiers::SUBCOMMAND_RESOLVE
        Commands::CloseIncident.execute(command)
      when Identifiers::SUBCOMMAND_CANCEL
        Commands::CancelIncident.execute(command)
      when Identifiers::SUBCOMMAND_REOPEN
        Commands::ReopenIncident.execute(command)
      when Identifiers::SUBCOMMAND_POSTMORTEM
        Commands::GeneratePostmortem.execute(command)
      when Identifiers::SUBCOMMAND_CATCHUP
        Commands::GenerateCatchup.execute(command)
      when Identifiers::SUBCOMMAND_TIMELINE
        Commands::ShowTimeline.execute(command)
      when Identifiers::SUBCOMMAND_LIST
        Commands::ListActiveIncidents.execute(command)
      when Identifiers::SUBCOMMAND_SHOUTOUT
        Commands::GiveShoutout.execute(command)
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
