# A card in a chat can show a token Firefight minted for an API key or an agent, which has no connection tool behind it.
class LetAChatCardShowAFirefightToken < ActiveRecord::Migration[8.1]
  def change
    change_column_null :chat_secret_entries, :integration_tool_id, true
    add_reference :chat_secret_entries, :api_key, type: :uuid, foreign_key: { on_delete: :cascade }, index: true
  end
end
