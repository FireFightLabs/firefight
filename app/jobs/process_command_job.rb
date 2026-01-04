# Background job to process slash commands
#
# TIMING REQUIREMENTS:
# - Controller responds to Slack in <3 seconds (handled by immediate 200 OK response)
# - Slack trigger_id expires 3 seconds after slash command (for opening modals)
# - This job should ideally complete <3s for modal operations
# - For non-modal operations, this job can run longer without issues
class ProcessCommandJob < ApplicationJob
  queue_as :default

  # Process a platform-specific command
  #
  # @param platform [String] Platform identifier ('slack', 'teams', etc.)
  # @param payload [Hash] Platform-specific command payload
  def perform(platform, payload)
    # Convert platform-specific payload to generic Command object
    command = parse_command(platform, payload)

    # Validate command
    unless command.valid?
      Rails.logger.error("Invalid command: #{command.errors.full_messages.join(", ")}")
      return
    end

    # Dispatch to appropriate handler
    CommandDispatcher.dispatch(command)
  rescue StandardError => e
    # Log error
    Rails.logger.error("Error processing command: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # Attempt to notify user of error
    notify_error(command, e) if command
  end

  private

  # Parse platform-specific payload into Command object
  def parse_command(platform, payload)
    case platform
    when Platforms::SLACK
      Slack::CommandAdapter.parse(payload)
    when Platforms::TEAMS
      # Teams::CommandAdapter.parse(payload)
      raise NotImplementedError, "Teams support coming soon"
    else
      raise ArgumentError, "Unknown platform: #{platform}"
    end
  end

  # Notify user of error
  def notify_error(command, error)
    case command.platform
    when Platforms::SLACK
      workspace = command.workspace
      return unless workspace

      Slack::Client.post_ephemeral(
        workspace: workspace,
        channel: command.channel_id,
        user: command.user_id,
        text: "❌ An error occurred: #{error.message}"
      )
    end
  rescue StandardError => e
    # If error notification fails, just log it
    Rails.logger.error("Failed to notify user of error: #{e.message}")
  end
end
