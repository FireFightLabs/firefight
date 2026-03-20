module Commands
  module Firefight
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
          Commands::Firefight::HomeModalHandler.execute(command)
        when Identifiers::SUBCOMMAND_SUMMARY
          Commands::Firefight::SummaryHandler.execute(command)
        when Identifiers::SUBCOMMAND_LEAD
          Commands::Firefight::LeadHandler.execute(command)
        when Identifiers::SUBCOMMAND_STATUS
          Commands::Firefight::StatusHandler.execute(command)
        when Identifiers::SUBCOMMAND_UPDATE
          Commands::Firefight::UpdateHandler.execute(command)
        when Identifiers::SUBCOMMAND_SEVERITY
          Commands::Firefight::SeverityHandler.execute(command)
        when Identifiers::SUBCOMMAND_ESCALATE
          Commands::Firefight::EscalateHandler.execute(command)
        when Identifiers::SUBCOMMAND_INVITE
          Commands::Firefight::InviteHandler.execute(command)
        when Identifiers::SUBCOMMAND_ACTION, Identifiers::SUBCOMMAND_ACTIONS
          Commands::Firefight::ActionsHandler.execute(command)
        when Identifiers::SUBCOMMAND_FOLLOWUP, Identifiers::SUBCOMMAND_FOLLOWUPS
          Commands::Firefight::FollowupsHandler.execute(command)
        when Identifiers::SUBCOMMAND_LINK, Identifiers::SUBCOMMAND_RELATE, Identifiers::SUBCOMMAND_DUPLICATE
          Commands::Firefight::LinkHandler.execute(command)
        when Identifiers::SUBCOMMAND_CLOSE, Identifiers::SUBCOMMAND_RESOLVE
          Commands::Firefight::CloseHandler.execute(command)
        when Identifiers::SUBCOMMAND_REOPEN
          Commands::Firefight::ReopenHandler.execute(command)
        when Identifiers::SUBCOMMAND_POSTMORTEM
          Commands::Firefight::PostmortemHandler.execute(command)
        when Identifiers::SUBCOMMAND_TIMELINE
          Commands::Firefight::TimelineHandler.execute(command)
        when Identifiers::SUBCOMMAND_LIST
          Commands::Firefight::ListHandler.execute(command)
        when Identifiers::SUBCOMMAND_SHOUTOUT
          Commands::Firefight::ShoutoutHandler.execute(command)
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
end
