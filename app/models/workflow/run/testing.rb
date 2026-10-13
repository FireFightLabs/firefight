# A test run tries a draft from the canvas (Workflow::Run::Acting says who it acts as, and DefinedWorkflow::Steps::Base
# pretends every change but the ones the tester turned on). An output pinned on the draft stands in for its step, and a
# run can try one step with only the steps before it.
# A run started again from a later step takes the results of the steps before that step from the run it started from.
# What stands in is kept on the run, by step id, and the engine asks for it before running a step
# (DefinedWorkflow.stand_in).
module Workflow::Run::Testing
  extend ActiveSupport::Concern

  KEY_OUTPUT = Workflow::Version::Pins::KEY_OUTPUT
  KEY_ROUTE = Workflow::Version::Pins::KEY_ROUTE

  # The output, and the route when the step took one, that stands in for the step, or nil to run it.
  def stand_in_for(step_key)
    entry = stand_ins.to_h[step_key.to_s]
    entry.is_a?(Hash) && entry[KEY_OUTPUT].is_a?(Hash) ? entry : nil
  end

  def stood_in?(step_key) = stand_in_for(step_key).present?

  # What it ran: its own copy when it ran less than its version or a draft that changes, else its version.
  def ran_snapshot = snapshot.presence || version.snapshot
end
