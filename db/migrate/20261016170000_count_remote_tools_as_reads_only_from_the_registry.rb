# A remote server's own readOnlyHint no longer makes its tool a read, only the registry's list or an admin's mark does.
# Discovery runs on connect and refresh, so the tools already kept are classified again here without calling any server.
# Each tool keeps whether it is switched on, and a tool that changes moves to its connection's changes pack.
class CountRemoteToolsAsReadsOnlyFromTheRegistry < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_MCP).find_each do |integration|
      entry = IntegrationProvider.find(integration.provider)
      Ability::Role.filing_together(integration) do
        integration.tools.find_each do |tool|
          declared = entry.present? && entry.reads?(tool.name, declared: false)
          read = declared || tool.marked_read?
          next if tool.read_only? == read && tool.declared_read? == declared

          tool.update!(read_only: read, spec: tool.spec.to_h.merge(Integration::Tool::DECLARED_READ => declared))
        end
      end
    end
  end

  def down
  end
end
