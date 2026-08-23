module Commands
  class LinkIncident
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command can only be used in an active incident channel.") unless command.incident

      default_type = command.subcommand == Identifiers::SUBCOMMAND_DUPLICATE ? IncidentRelationship::DUPLICATE : IncidentRelationship::RELATED
      command.workspace.adapter.open_link_incident_modal(trigger_id: command.trigger_id, incident: command.incident, default_type: default_type)

      nil
    end
  end
end
