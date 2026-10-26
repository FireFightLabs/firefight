# Every night, Halon checks what each workspace remembers against production and merges what says the same thing
# (MemoryReviewService). One workspace failing never stops the others.
class MemoryReviewJob < ApplicationJob
  queue_as :background

  def perform(on = Date.current)
    Workspace.find_each do |workspace|
      review = MemoryReviewService.new(workspace).start!(on: on)
      Rails.logger.info({ event: "memory_review.started", workspace_id: workspace.id, memories: review.memory_ids.size, merged: review.merged }.to_json) if review
    rescue StandardError => error
      Rails.logger.error({ event: "memory_review.failed", workspace_id: workspace.id, error: error.class.name, message: error.message }.to_json)
    end
  end
end
