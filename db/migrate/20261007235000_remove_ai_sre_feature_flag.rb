# Halon is part of every workspace, so the switch that turned it on per workspace is gone.
class RemoveAiSreFeatureFlag < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM flipper_gates WHERE feature_key = 'ai_sre'"
    execute "DELETE FROM flipper_features WHERE key = 'ai_sre'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
