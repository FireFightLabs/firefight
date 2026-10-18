# Who is behind a run, a person, an agent or a key, beside the member who started it, so what a run starts in their name,
# such as an investigation, reaches no further than they could. Empty for a run its trigger started.
class AddAskedByToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :workflow_runs, :asked_by, polymorphic: true, type: :uuid, index: true
  end
end
