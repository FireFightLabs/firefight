# Background job to process slash commands
# Must complete within 3 seconds due to Slack trigger_id expiration
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
    when "slack"
      Slack::CommandAdapter.parse(payload)
    when "teams"
      # Teams::CommandAdapter.parse(payload)
      raise NotImplementedError, "Teams support coming soon"
    else
      raise ArgumentError, "Unknown platform: #{platform}"
    end
  end

  # Notify user of error
  def notify_error(command, error)
    case command.platform
    when "slack"
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
