module Ability
  # A ledger row or an approval keeps principal_label, the machine label such as "api_key:Deploy bot", so logs and the
  # record still say who it was once the principal is gone. A person reads only the name, the principal's own while it
  # exists, so a rename or Halon's name shows on old rows too.
  module PrincipalNamed
    extend ActiveSupport::Concern

    # Reads every record's principal, and a person's user, in two queries, for a list of ledger rows or approvals.
    def self.with_principal_names(records)
      records = records.to_a
      ActiveRecord::Associations::Preloader.new(records: records, associations: [ :principal ]).call
      ::Principal.preload_users(records.map(&:principal))
      records
    end

    class_methods do
      def with_principal_names(records) = PrincipalNamed.with_principal_names(records)
    end

    # A call Halon made in a member's chat runs with the member's access, so it reads as Halon and names whose access it
    # used, as the chat's request in Slack says Halon wants to.
    def principal_name
      return "#{SystemAgent::HALON}, for #{principal_own_name}" if source == AbilityGateway::SOURCE_CONVERSATION && principal_type == WorkspaceMembership.name

      principal_own_name
    end

    # The principal's own name, the person whose access a chat's call used rather than Halon.
    def principal_own_name = principal&.actor_display_name || principal_label.to_s.split(":", 2).last
  end
end
