module Commands
  # Handles opening the incident creation modal
  # Platform-agnostic handler that delegates to platform-specific clients
  class ModalHandler
    # Execute the modal opening
    #
    # @param command [Command] Platform-agnostic command object
    # @return [void]
    def self.execute(command)
      case command.platform
      when Platforms::SLACK
        execute_slack(command)
      when Platforms::TEAMS
        execute_teams(command)
      else
        raise ArgumentError, "Unsupported platform: #{command.platform}"
      end
    end

    # Open Slack modal
    private_class_method def self.execute_slack(command)
      workspace = command.workspace
      raise ArgumentError, "Workspace not found" unless workspace

      # Build modal view
      modal_view = Slack::ModalBuilder.incident_creation_form

      # Open modal using Slack API
      Slack::Client.open_modal(
        workspace: workspace,
        trigger_id: command.trigger_id,
        view: modal_view
      )
    rescue Slack::Client::TriggerExpiredError
      # Trigger ID expired (>3 seconds since command)
      # Post ephemeral message as fallback
      Slack::Client.post_ephemeral(
        workspace: workspace,
        channel: command.channel_id,
        user: command.user_id,
        text: "⏰ The command timed out. Please try `/firefight` again."
      )
    rescue Slack::Client::ApiError => e
      # Log error and notify user
      Rails.logger.error("Slack API error: #{e.message}")
      Slack::Client.post_ephemeral(
        workspace: workspace,
        channel: command.channel_id,
        user: command.user_id,
        text: "❌ Sorry, something went wrong. Please try again."
      )
    end

    # Open Teams modal (future implementation)
    private_class_method def self.execute_teams(command)
      # TODO: Implement Teams modal opening
      raise NotImplementedError, "Teams support coming soon"
    end
  end
end
