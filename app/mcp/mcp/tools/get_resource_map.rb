module Mcp
  module Tools
    # The map read off the workspace's connections, so an agent starts from what is known rather than listing each
    # provider again. Facts only, never live values: a status here is what the last sweep saw.
    class GetResourceMap < Base
      tool_name GET_RESOURCE_MAP
      authorize_as Ability::Action::RESOURCE_MAP
      description "The first place to find which provider and account hold a named domain, zone, service or database. " \
                  "It only reads, so look here before asking a person or using a provider's own tools. " \
                  "What runs where, read off the workspace's connections: services, build services, databases and " \
                  "branches, jobs, repositories and domains, and at the edge zones, Workers, Pages sites, buckets, KV " \
                  "namespaces, queues, database proxies, tunnels, load balancers and their pools, and Access applications, " \
                  "by provider and account, with how they depend on each other and which repository each is managed in " \
                  "as code, such as Terraform or Helm, so a fix to one goes to that code. A zone's details carry its SSL mode, " \
                  "certificates and rule counts, and a change to them is recorded. " \
                  "Without a resource, the whole map, one line per resource. With a resource, its fact sheet: where it " \
                  "runs, its page, the catalog services it runs with what each is for and who owns it, what people " \
                  "confirmed about it, how its recent incidents ended, what normal looks like for its metrics over the last " \
                  "week, and every link within two hops, each saying how it was found. A status is what the " \
                  "last sweep saw, so check live state with the provider's own tools. A link marked not confirmed is a " \
                  "suggestion. Never state it as fact, and say it is unconfirmed if you rely on it. It holds only what runs in the " \
                  "environments the caller may read, and a sheet counts the links it leaves out for that reason. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          resource: { type: "string", description: "A resource's name or its provider's id, such as web or firefight-prod/main. Leave it out for the whole map" }
        }
      )

      SHEETS_SHOWN = 5
      MAP_LINES = 300

      # Only what the principal reads. Naming a resource outside it reads as naming nothing, and a link to one is counted, never named.
      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        return respond(overview(workspace, visible, ResourceMap::Resource.environments_visible_to(principal, workspace))) if args[:resource].blank?

        found = visible.named(workspace, args[:resource]).includes(integration_environment: %i[integration environment]).to_a
        if found.empty?
          return respond(error: "Nothing called #{args[:resource]} is on the map. Leave the resource out to see the whole map.")
        end

        more = "#{found.size - SHEETS_SHOWN} more share this name, name one by its provider's id" if found.size > SHEETS_SHOWN
        respond({ resources: found.first(SHEETS_SHOWN).map { |resource| sheet(resource, visible) }, more: more }.compact)
      end

      def self.overview(workspace, visible, environments)
        resources = visible.present.order(:provider, :account, :kind, :name).to_a
        accounts = resources.first(MAP_LINES).group_by { |resource| [ resource.provider, resource.account ] }.map do |(provider, account), grouped|
          { provider: provider, account: account, resources: grouped.map { |resource| line(resource) } }
        end
        {
          accounts: accounts, connections: connections(workspace, environments),
          left_out: (resources.size > MAP_LINES ? "#{resources.size - MAP_LINES} more resources are on the map, name one to read it" : nil)
        }.compact
      end

      def self.sheet(resource, visible)
        hidden = resource.links_out_of_reach(visible)
        environment_row = resource.integration_environment
        entries = resource.catalog_entries.active.includes(:catalog_type, outgoing_relationships: { target_entry: :catalog_type }).to_a
        {
          name: resource.name, kind: resource.kind, provider: resource.provider, account: resource.account,
          environment: environment_row&.environment&.name, id: resource.external_id, status: resource.status, page: resource.url,
          details: resource.details.presence, first_seen: resource.first_seen_at.iso8601, last_seen: resource.last_seen_at.iso8601,
          removed: resource.removed_at && "Not seen by its connection since #{resource.removed_at.iso8601}",
          runs: runs(entries).presence, confirmed: confirmed(resource, entries).presence,
          past_incidents: past_incidents(resource.workspace, entries).presence,
          normal: (resource.baselines.fresh.order(:label).map(&:line).presence unless resource.removed_at),
          links: resource.neighborhood(within: visible).map { |link, hop| link_line(link, hop) },
          out_of_reach: (hidden.positive? ? "#{hidden} more #{'link'.pluralize(hidden)} within two hops #{hidden == 1 ? 'leads' : 'lead'} to resources in environments you cannot read" : nil)
        }.compact
      end

      # The catalog services it runs, with what each is for and who owns it, as people wrote them in the catalog.
      def self.runs(entries)
        entries.map do |entry|
          owners = entry.owning_teams.map(&:name)
          [ "#{entry.name} (#{entry.catalog_type.name})#{", owned by #{owners.to_sentence}" if owners.any?}", entry.purpose ].compact.join(". ")
        end
      end

      # What people confirmed about it or its services. Unconfirmed memories stay with recall, since they are hunches.
      def self.confirmed(resource, entries)
        Chat::Memory.where(workspace: resource.workspace, state: Chat::Memory::STATE_CONFIRMED).where(subject: [ resource ] + entries)
                    .includes(:subject, confirmed_by: :user).most_trusted_first.limit(Chat::Memory::STARTING_LIMIT).map(&:line)
      end

      def self.past_incidents(workspace, entries)
        Incident.past_on(workspace, entries.map(&:id)).map(&:incident).uniq.sort_by(&:ended_at).reverse
                .first(Incident::Outcome::PAST_SHOWN).map do |incident|
          outcome = incident.outcome
          ended = "#{incident.identifier} #{incident.name}, ended #{incident.ended_at.to_date.iso8601}"
          outcome ? "#{ended}: #{outcome.text} (#{outcome.source.downcase_first})" : "#{ended}: nothing was written about how it ended"
        end
      end

      def self.line(resource) = [ resource.kind, resource.name, resource.status ].compact.join(", ")

      def self.link_line(link, hop)
        how = case link.origin
        when ResourceMap::ORIGIN_DECLARED then "declared by #{link.integration_environment&.integration&.name || 'a provider'}"
        when ResourceMap::ORIGIN_MATCHED then "matched from what the providers report"
        when ResourceMap::ORIGIN_PERSON then "added by a person"
        when ResourceMap::ORIGIN_INFERRED
          link.confirmed_at ? "suggested by Firefight, confirmed by a person" : "suggested by Firefight, #{link.certainty}, not confirmed: #{link.clues.join('. ')}"
        else link.confirmed_at ? "suggested by Halon, confirmed by a person" : "suggested by Halon, not confirmed"
        end
        "#{link.sentence} (#{how}#{', two links away' if hop > 1})#{": #{link.note}" if link.note.present?}"
      end

      # What each connection could not read, so a missing resource is known to be missing rather than absent. Only rows
      # wired to an environment the principal reads, since a gap can name what it could not read.
      def self.connections(workspace, environments)
        rows = IntegrationEnvironment.joins(:integration).merge(Integration.active).where(integrations: { workspace_id: workspace.id })
        rows = rows.where(catalog_entry_id: environments) unless environments.nil?
        rows = rows.includes(:integration)
        rows.select { |row| row.map_swept_at || row.map_error }.map do |row|
          { connection: row.integration.name, swept: row.map_swept_at&.iso8601, error: row.map_error, gaps: row.map_gaps.presence }.compact
        end
      end
    end
  end
end
