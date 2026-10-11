# Opsgenie's pack gained tools, which reach a connection only through discovery, and Firefight paging is granted the
# tools each paging connection raises and keeps pages in step through. A connection made from now on gets both when it
# is made. Opsgenie's tools are declared in code, so discovery here calls no provider.
class GrantPagingToExistingConnections < ActiveRecord::Migration[8.1]
  def up
    Integration.active.find_each do |integration|
      next unless Integrations::Paging.pages?(integration.provider)

      Integrations::DiscoveryService.sync!(integration) if integration.native?
      integration.workspace.grant_paging!(integration)
    end
  end

  def down
  end
end
