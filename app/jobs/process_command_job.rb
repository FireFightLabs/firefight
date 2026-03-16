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
    command = parse_command(platform, payload)

    unless command.valid?
      Rails.logger.error({ event: "process_command_job.invalid_command", errors: command.errors.full_messages })
      return
    end

    result = CommandDispatcher.dispatch(command)
    send_ephemeral(command, result)
  rescue ArgumentError, NotImplementedError
    raise
  rescue StandardError => e
    Rails.logger.error({ event: "process_command_job.failed", workspace_id: command&.workspace&.id, error: e.message, backtrace: e.backtrace&.first(5) })
    notify_error(command, e) if command
  end

  private

  # Parse platform-specific payload into Command object
  def parse_command(platform, payload)
    case platform
    when Platforms::SLACK
      Slack::CommandAdapter.parse(payload)
    when Platforms::TEAMS
      raise NotImplementedError, "Teams support coming soon"
    else
      raise ArgumentError, "Unknown platform: #{platform}"
    end
  end

  # Send ephemeral response to user when handler returns one
  def send_ephemeral(command, result)
    return unless result.is_a?(Hash) && result[:response_type] == Command::EPHEMERAL

    workspace = command.workspace
    return unless workspace

    workspace.adapter.post_ephemeral(
      channel_id: command.channel_id,
      user_id: command.user_id,
      text: result[:text],
      blocks: result[:blocks]
    )
  rescue StandardError => e
    Rails.logger.error({ event: "process_command_job.send_ephemeral_failed", error: e.message })
  end

  # Notify user of error
  def notify_error(command, error)
    workspace = command.workspace
    return unless workspace

    workspace.adapter.post_ephemeral(
      channel_id: command.channel_id,
      user_id: command.user_id,
      text: "Sorry, something went wrong. Please try again."
    )
  rescue StandardError => e
    Rails.logger.error({ event: "process_command_job.notify_error_failed", error: e.message })
  end
end
