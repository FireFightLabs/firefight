# A specialist is a helper that reads one kind of system for Halon. domain names that kind, and proposals keeps the
# changes it proposed, encrypted, so the asking turn can tell Halon what each would take.
class AddSpecialistToChatHelpers < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_helpers, :domain, :string
    add_column :chat_helpers, :proposals, :text
  end
end
