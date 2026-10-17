# A change Halon made without asking before undo steps were marked declared was given its undo from the registry, the
# only undo such a change ever had, so its steps are marked declared and Undo keeps running them. A temporary change's
# undo from before was written by a model, so it is left unmarked and goes to the chat.
class MarkRegistryUndosAsDeclared < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE chat_mitigations
      SET undo_steps = (SELECT jsonb_agg(step || '{"declared": true}'::jsonb) FROM jsonb_array_elements(undo_steps) AS step), updated_at = now()
      WHERE undo_state = 'ready' AND unasked_reason IS NOT NULL AND duration_minutes IS NULL AND jsonb_array_length(undo_steps) > 0
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Which steps were marked is not kept."
  end
end
