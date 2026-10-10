# Every minute, a run for each plan whose approved time came. The claim in Conversation::Plans.run_scheduled! means a
# plan picked up by two sweeps still starts once.
class ChatPlanSweepJob < ApplicationJob
  queue_as :background

  def perform(now = Time.current)
    Chat::Plan.where(status: Chat::Plan::STATUS_SCHEDULED, run_at: ..now).pluck(:id).each { |id| ChatPlanRunJob.perform_later(id) }
  end
end
