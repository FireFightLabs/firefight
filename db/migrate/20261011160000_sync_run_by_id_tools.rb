# The platforms' run history tools read one run by its id with its phases, their log reads take the run they belong to,
# and the clouds gained a read of their build services' builds. Discovery only runs on connect or refresh, so existing
# connections get the new tools and arguments here. Native packs declare their tools locally, so this calls no provider.
class SyncRunByIdTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
