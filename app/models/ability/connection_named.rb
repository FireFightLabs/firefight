module Ability
  # A tool's action key names its connection by slug, which reads like the provider's name when a connection is named
  # after it. A ledger row or an approval shown to a person names the connection the way they tell it apart instead,
  # such as "Faylee (Northflank)". nil for a system action.
  module ConnectionNamed
    extend ActiveSupport::Concern

    class_methods do
      # Reads every record's connection in one query, for a list.
      def with_connection_names(records)
        records = records.to_a
        records.group_by(&:workspace_id).each do |workspace_id, those|
          names = Integration.display_names_for(workspace_id, those.map(&:action_key))
          those.each { |record| record.connection_name = names[record.action_key] }
        end
        records
      end
    end

    attr_writer :connection_name

    def connection_name
      return @connection_name if defined?(@connection_name)

      @connection_name = Integration.display_names_for(workspace_id, [ action_key ])[action_key]
    end
  end
end
