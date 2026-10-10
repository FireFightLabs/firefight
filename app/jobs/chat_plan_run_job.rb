# Starts one scheduled plan, after a fresh reading of how things stand. On the conversations queue, beside the turn it
# hands the plan to.
class ChatPlanRunJob < ApplicationJob
  queue_as :conversations

  # Every sweep queues a plan still waiting, and Halon's reading can take longer than a minute, so one runs at a time.
  limits_concurrency key: ->(plan_id) { plan_id }, duration: 15.minutes

  def perform(plan_id)
    plan = Chat::Plan.find_by(id: plan_id)
    Conversation::Plans.run_scheduled!(plan) if plan
  end
end
