# GitHub's pack now lists and sets Actions secrets, and Northflank's adds a webhook trigger to a workflow. Discovery only
# runs on connect or refresh, so existing connections get them here. Native packs declare their tools locally, so this
# calls no provider. New tools arrive switched on, and join each connection's packs by whether they only read.
class SyncSecretHandoffTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
