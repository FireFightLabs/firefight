module Commands
  module Firefight
    # Routes /firefight and /ff subcommands to appropriate handlers
    # Platform-agnostic — works with any Command object
    class HomeHandler
      SUBCOMMANDS = Identifiers.constants
        .select { |c| c.to_s.start_with?("SUBCOMMAND_") }
        .map { |c| Identifiers.const_get(c) }
        .freeze

      # Execute the appropriate subcommand
      #
      # @param command [Command] Platform-agnostic command object
      # @return [Hash, void] Response hash or handler result
      def self.execute(command)
        subcommand = command.subcommand&.downcase

        case subcommand
        when Identifiers::SUBCOMMAND_NEW
          Commands::ModalHandler.execute(command)
        when Identifiers::SUBCOMMAND_HOME, nil
          open_home_modal(command)
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
          ephemeral("Postmortem command coming soon...")
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
          ephemeral(msg)
        end
      rescue => e
        Rails.logger.error({
          event: "firefight.command_error",
          command: command.text,
          subcommand: subcommand,
          error: e.message,
          backtrace: e.backtrace&.first(5)
        }.to_json)

        ephemeral("Sorry, something went wrong. Please try again.")
      end

      private_class_method def self.open_home_modal(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first

        if incident
          workspace.adapter.open_home_modal(trigger_id: command.trigger_id, channel_id: command.channel_id)
        else
          workspace.adapter.open_incident_creation_modal(trigger_id: command.trigger_id)
        end
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff` again.")
      end

      private_class_method def self.suggest_subcommand(input)
        checker = DidYouMean::SpellChecker.new(dictionary: SUBCOMMANDS)
        checker.correct(input).first
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
