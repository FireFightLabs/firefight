# A credential for an agent, so the token and the identity are separate
# things: rotating one mints a second token on the same agent and revokes the
# first, and the agent's grants and history never move.
class AddAgentToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_keys, :agent, type: :uuid, foreign_key: true, index: true
  end
end
