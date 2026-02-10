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
          # Phase 2.1
          ephemeral("Summary command coming soon...")
        when "lead"
          # Phase 2.2
          ephemeral("Lead command coming soon...")
        when "status"
          # Phase 3.1
          ephemeral("Status command coming soon...")
        when "severity"
          # Phase 3.2
          ephemeral("Severity command coming soon...")
        when "escalate"
          # Phase 4.5
          ephemeral("Escalate command coming soon...")
        when "action", "actions"
          # Phase 4.1
          ephemeral("Actions command coming soon...")
        when "close", "resolve"
          # Phase 5.1
          ephemeral("Close command coming soon...")
        when "postmortem"
          # Phase 5.2
          ephemeral("Postmortem command coming soon...")
        when "timeline"
          # Phase 6.1
          ephemeral("Timeline command coming soon...")
        when "list"
          # Phase 6.2
          ephemeral("List command coming soon...")
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
        adapter.open_modal(
          trigger_id: command.trigger_id,
          view: Slack::ModalBuilder.home_modal
        )
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
