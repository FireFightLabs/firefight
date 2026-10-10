class AddChatHelperToInvestigationSteps < ActiveRecord::Migration[8.1]
  def change
    add_reference :investigation_steps, :chat_helper, type: :uuid, foreign_key: { on_delete: :nullify }
  end
end
