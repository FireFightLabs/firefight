class AddOneCurrentInstructionPerPlace < ActiveRecord::Migration[8.1]
  def change
    # The whole workspace has no scope, so the blanks are coalesced to count as one place.
    add_index :chat_instructions,
              "workspace_id, COALESCE(scope_type, ''), COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)",
              unique: true, where: "superseded_at IS NULL", name: "index_chat_instructions_one_current_per_place"
  end
end
