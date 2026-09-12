# New pack tools reach a connection through discovery, which until now only ran when
# someone connected or refreshed one. A native pack declares its tools in code, so this
# is a database write with no call to the provider. New rows arrive disabled, as always.
class SyncNativeIntegrationTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
