# The setup checklist after the founder's letter. Each step a person answers keeps its answer here, so the checklist
# picks up where it was left on any device. Steps that are facts elsewhere (Slack, the test incident) are read from there.
class AddChecklistToWorkspaceOnboardings < ActiveRecord::Migration[8.1]
  def change
    change_table :workspace_onboardings, bulk: true do |t|
      t.string :ai_choice
      t.datetime :ai_chosen_at
      t.jsonb :stack_answers, null: false, default: {}
      t.datetime :stack_done_at
      t.datetime :permissions_reviewed_at
      t.datetime :halon_answered_at
      t.datetime :slack_skipped_at
      t.datetime :checklist_completed_at
    end
  end
end
