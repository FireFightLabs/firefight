# Existing GitHub connections learn the tools that read code in a sandbox, and the ones added for what changed before an
# incident. Native packs declare their tools locally, so this calls no provider. New rows arrive disabled.
class OfferCodeReadingToolsToExistingConnections < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
