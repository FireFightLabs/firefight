# Fly.io's pack gained starting, stopping, suspending and cordoning machines and a Managed Postgres cluster's queries,
# Vercel's canceling and redeploying a deployment, its rolling releases and Vercel CI runs, and Netlify's locking,
# canceling and building a deploy. Discovery only runs on connect or refresh, so existing connections get them here.
# Native packs declare their tools locally, so this calls no provider.
class SyncFlyVercelNetlifyChangeTools < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[fly vercel netlify].freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDERS).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
