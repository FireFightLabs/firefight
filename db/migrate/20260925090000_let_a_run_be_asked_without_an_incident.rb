# A run can answer a question nobody has declared an incident for. It then answers where it was asked, in a channel or
# in the chat that started it, whose card finds the run by the tool call that asked for it.
class LetARunBeAskedWithoutAnIncident < ActiveRecord::Migration[8.1]
  def change
    change_column_null :investigations, :subject_type, true
    change_column_null :investigations, :subject_id, true
    add_column :investigations, :channel_id, :string
    add_reference :investigations, :conversation, type: :uuid, foreign_key: { on_delete: :nullify }
    add_column :investigations, :tool_call_id, :string
    add_column :investigation_findings, :suggests_incident, :boolean, default: false, null: false
  end
end
