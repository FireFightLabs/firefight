# Posts or redraws a plan's message where its chat lives. One at a time per plan, so a redraw never lands before the post
# it redraws, and each draws the plan as it stands when it runs.
class ChatPlanMessageJob < ApplicationJob
  queue_as :conversations

  limits_concurrency key: ->(plan_id) { plan_id }, duration: 2.minutes

  def perform(plan_id)
    plan = Chat::Plan.find_by(id: plan_id)
    Conversation::Plans.tell!(plan) if plan
  end
end
