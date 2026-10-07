# GitHub's pack now reads and changes pull requests, issues, releases, branches, checks and security alerts, and lists
# workflows. Discovery only runs on connect or refresh, so existing connections get them here. Native packs declare their
# tools locally, so this calls no provider. New tools arrive switched on, and join each connection's packs by whether
# they only read.
class SyncGithubFullTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
