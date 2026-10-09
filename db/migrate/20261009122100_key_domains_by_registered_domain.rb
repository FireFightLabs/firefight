# A hostname's account on the map is now its registered domain, so api.acme.co.uk is under acme.co.uk rather than
# co.uk. Rows already on the map move across, so the next sweep finds them rather than adding each hostname again.
class KeyDomainsByRegisteredDomain < ActiveRecord::Migration[8.1]
  class Resource < ActiveRecord::Base
    self.table_name = "resource_map_resources"
  end

  def up
    Resource.where(provider: "dns", kind: "domain").find_each do |row|
      account = PublicSuffix.domain(row.external_id, ignore_private: true)
      next if account.nil? || account == row.account
      next if Resource.exists?(workspace_id: row.workspace_id, provider: row.provider, account: account, kind: row.kind, external_id: row.external_id)

      row.update_columns(account: account)
    end
  end

  def down; end
end
