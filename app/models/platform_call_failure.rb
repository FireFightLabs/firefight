# A platform call that failed. Written where the platform's answer is read, so every caller is covered, and never
# allowed to break the call it records. The adapter decides which answers are failures worth keeping.
class PlatformCallFailure < ApplicationRecord
  KEPT_FOR = 30.days
  MESSAGE_LIMIT = 1_000

  belongs_to :workspace

  scope :recent, -> { order(created_at: :desc) }
  scope :in_channel, ->(channel_id) { where(channel_id: channel_id) }

  def self.note(workspace:, platform:, operation:, error:, channel_id: nil)
    return if workspace.nil?

    create!(
      workspace: workspace, platform: platform, operation: operation.to_s, error_class: error.class.name,
      message: error.message.to_s.truncate(MESSAGE_LIMIT), channel_id: channel_id.presence
    )
  rescue StandardError => failure
    Rails.logger.warn({ event: "platform_call_failure.unrecorded", operation: operation, error: failure.message }.to_json)
    nil
  end

  def self.cleanup
    BatchedDelete.run(where(created_at: ...KEPT_FOR.ago), label: "platform_call_failures.cleanup")
  end
end
