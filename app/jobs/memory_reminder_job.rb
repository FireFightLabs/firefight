# Once a week, reminds whoever should know about memories nobody confirmed, in workspaces where Halon is available and a
# chat platform is connected. A platform hiccup only loses the message, and the memories wait on the Memory page.
class MemoryReminderJob < ApplicationJob
  queue_as :background

  def perform
    Workspace.where.not(platform: nil).find_each do |workspace|
      next unless Investigation.available_for?(workspace)

      sent = MemoryPostService.new(workspace).remind!
      Rails.logger.info({ event: "memory_reminder.sent", workspace_id: workspace.id, messages: sent }.to_json) if sent.positive?
    rescue AdapterError => error
      Rails.logger.info({ event: "memory_reminder.failed", workspace_id: workspace.id, error: error.class.name }.to_json)
    end
  end
end
