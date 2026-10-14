# A workflow's question can be a Manual step's task, open to one person or anyone and posted in a channel for anyone,
# and its choices are labels the builder wrote, each with the key its route is named by. An approval keeps why it was
# withdrawn, so where it was asked can say so.
class LetWorkflowQuestionsHoldTasksAndLabelledChoices < ActiveRecord::Migration[8.1]
  def up
    add_column :workflow_run_questions, :kind, :string, null: false, default: "question"
    add_column :workflow_run_questions, :open_to_anyone, :boolean, null: false, default: false
    add_column :workflow_run_questions, :channel_id, :string
    add_column :workflow_run_questions, :labelled_choices, :jsonb, null: false, default: []
    execute <<~SQL.squish
      UPDATE workflow_run_questions SET labelled_choices = COALESCE((
        SELECT jsonb_agg(jsonb_build_object('key', choice, 'label', upper(left(replace(choice, '_', ' '), 1)) || substr(replace(choice, '_', ' '), 2)) ORDER BY place)
        FROM unnest(choices) WITH ORDINALITY AS listed(choice, place)
      ), '[]'::jsonb)
    SQL
    remove_column :workflow_run_questions, :choices
    rename_column :workflow_run_questions, :labelled_choices, :choices

    add_column :ability_approvals, :withdrawn_reason, :text
  end

  def down
    remove_column :ability_approvals, :withdrawn_reason
    add_column :workflow_run_questions, :keyed_choices, :string, array: true, null: false, default: []
    execute "UPDATE workflow_run_questions SET keyed_choices = ARRAY(SELECT jsonb_array_elements(choices) ->> 'key')"
    remove_column :workflow_run_questions, :choices
    rename_column :workflow_run_questions, :keyed_choices, :choices
    remove_column :workflow_run_questions, :channel_id
    remove_column :workflow_run_questions, :open_to_anyone
    remove_column :workflow_run_questions, :kind
  end
end
