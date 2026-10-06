module Ability
  # A tool's action key names its connection by slug, which reads like the provider's name when a connection is named
  # after it. A ledger row or an approval shown to a person names the connection the way they tell it apart instead,
  # such as "Faylee (Northflank)", and its provider. nil for a system action.
  module ConnectionNamed
    extend ActiveSupport::Concern

    # Reads every record's connection in one query, for a list of ledger rows or approvals.
    def self.with_connection_names(records)
      records = records.to_a
      records.group_by(&:workspace_id).each do |workspace_id, those|
        found = Integration.connections_for(workspace_id, those.map(&:action_key))
        those.each { |record| record.tool_connection = found[record.action_key] }
      end
      records
    end

    class_methods do
      def with_connection_names(records) = ConnectionNamed.with_connection_names(records)
    end

    attr_writer :tool_connection

    def connection_name = tool_connection&.display_name

    # The provider's key, such as northflank, for a caller that groups by provider.
    def connection_provider = tool_connection&.provider

    private

    def tool_connection
      return @tool_connection if defined?(@tool_connection)

      @tool_connection = Integration.connections_for(workspace_id, [ action_key ])[action_key]
    end
  end
end
