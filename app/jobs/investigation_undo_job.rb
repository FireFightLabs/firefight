# Writes a fix's undo away from the click, since it asks a model.
class InvestigationUndoJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(plan_id) { plan_id }, duration: 10.minutes

  def perform(plan_id)
    plan = Investigation::RemediationPlan.find_by(id: plan_id)
    return unless plan&.writing_undo?

    Investigation::UndoWriter.new(plan).write!
  end
end
