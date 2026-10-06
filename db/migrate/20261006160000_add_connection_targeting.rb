class AddConnectionTargeting < ActiveRecord::Migration[8.1]
  def change
    # The connections a chat's tools were last offered against, so a change made while the chat goes on is told to it.
    add_column :chats, :connections_seen, :jsonb
    # What a call waiting for the person reaches, worked out from the tool when it was asked, never from the agent's words.
    add_column :ruby_llm_tool_calls, :target, :string
  end
end
