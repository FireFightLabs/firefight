# Halon reads how things stand now for a fix's step once it was approved, before someone runs it.
class FixStepCheckJob < ApplicationJob
  queue_as :conversations

  def perform(step_id)
    step = Investigation::RemediationStep.find_by(id: step_id)
    Investigation::FixRunner.check!(step) if step
  end
end
