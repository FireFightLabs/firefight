# A workspace can turn Halon's nightly memory check off, and each line of a memory's history keeps the run that checked
# it, so the Memory page can link Halon's evidence to the run that found it.
class AddMemoryReviewSettingAndRunToMemoryHistory < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :memory_review_enabled, :boolean, null: false, default: true
    add_reference :chat_memory_events, :investigation, type: :uuid, foreign_key: { on_delete: :nullify }
  end
end
