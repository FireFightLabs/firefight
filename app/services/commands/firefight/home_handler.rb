module Commands
  module Firefight
    # Routes /firefight and /ff subcommands to appropriate handlers
    # Platform-agnostic — works with any Command object
    class HomeHandler
      # Execute the appropriate subcommand
      #
      # @param command [Command] Platform-agnostic command object
      # @return [Hash, void] Response hash or handler result
      def self.execute(command)
        subcommand = command.subcommand&.downcase

        case subcommand
        when "new"
          # Delegate to existing modal handler for incident creation
          Commands::ModalHandler.execute(command)
        when "home", nil
          open_home_modal(command)
        when "summary"
          Commands::Firefight::SummaryHandler.execute(command)
        when "lead"
          Commands::Firefight::LeadHandler.execute(command)
        when "status"
          Commands::Firefight::StatusHandler.execute(command)
        when "update"
          Commands::Firefight::UpdateHandler.execute(command)
        when "severity"
          Commands::Firefight::SeverityHandler.execute(command)
        when "escalate"
          Commands::Firefight::EscalateHandler.execute(command)
        when "invite"
          Commands::Firefight::InviteHandler.execute(command)
        when "action", "actions"
          Commands::Firefight::ActionsHandler.execute(command)
        when "followup", "followups"
          Commands::Firefight::FollowupsHandler.execute(command)
        when "link", "relate", "duplicate"
          Commands::Firefight::LinkHandler.execute(command)
        when "close", "resolve"
          Commands::Firefight::CloseHandler.execute(command)
        when "reopen"
          Commands::Firefight::ReopenHandler.execute(command)
        when "postmortem"
          # Phase 5.2
          ephemeral("Postmortem command coming soon...")
        when "timeline"
          Commands::Firefight::TimelineHandler.execute(command)
        when "list"
          Commands::Firefight::ListHandler.execute(command)
        when "shoutout"
          Commands::Firefight::ShoutoutHandler.execute(command)
        else
          ephemeral("Unknown subcommand: `#{subcommand}`. Type `/ff` for available commands.")
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

        adapter = WorkspaceAdapter.for(workspace)
        incident = workspace.incidents.active.in_channel(command.channel_id).first

        if incident
          adapter.open_home_modal(trigger_id: command.trigger_id, channel_id: command.channel_id)
        else
          adapter.open_incident_creation_modal(trigger_id: command.trigger_id)
        end
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
