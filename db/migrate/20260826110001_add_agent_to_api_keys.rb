# Token and identity are separate, so rotating mints a second token on the same agent
# and its grants and history never move.
class AddAgentToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_keys, :agent, type: :uuid, foreign_key: true, index: true
  end
end
