# Stops using what Halon learned and nobody confirmed in time, in workspaces that chose a window. Off by default.
class MemoryExpiryJob < ApplicationJob
  queue_as :background

  def perform
    Workspace.where.not(memory_expiry_days: nil).find_each do |workspace|
      expired = Chat::Memory.expire!(workspace)
      Rails.logger.info({ event: "memory_expiry.expired", workspace_id: workspace.id, memories: expired }.to_json) if expired.positive?
    end
  end
end
