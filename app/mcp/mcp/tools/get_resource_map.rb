module Mcp
  module Tools
    # The map read off the workspace's connections, so an agent starts from what is known rather than listing each
    # provider again. Facts only, never live values: a status here is what the last sweep saw.
    class GetResourceMap < Base
      extend MapPayloads

      SHEETS_SHOWN = 5
      # From this many resources the map is given as its numbers rather than one line each.
      MAP_LINES = 300
      MOST_DEPENDED_ON = 10
      # What a count by environment calls resources only a connection wired to no environment reports.
      NO_ENVIRONMENT = "no environment".freeze

      tool_name GET_RESOURCE_MAP
      authorize_as Ability::Action::RESOURCE_MAP
      description "The first place to find which provider and account hold a named domain, zone, service or database. " \
                  "It only reads, so look here before asking a person or using a provider's own tools. " \
                  "What runs where, read off the workspace's connections, every kind the map holds " \
                  "(#{ResourceMap::KINDS.map { |kind| kind.tr('_', ' ').pluralize }.to_sentence}), " \
                  "by provider and account, with how they depend on each other and which repository each is managed in " \
                  "as code, such as Terraform or Helm, so a fix to one goes to that code. A zone's details carry its SSL mode, " \
                  "certificates and rule counts, and a change to them is recorded. " \
                  "Without a resource, the whole map one line per resource, or from #{MAP_LINES} resources its numbers " \
                  "by provider, kind, environment and health with the most depended on. With a resource, its fact sheet: where it " \
                  "runs, its page, the catalog services it runs with what each is for and who owns it, what people " \
                  "confirmed about it, how its recent incidents ended, what normal looks like for its metrics over the last " \
                  "week, its key checks with their normal (run_key_query runs one), the log lines it usually prints (new_log_patterns " \
                  "finds the ones it does not), and every link within two hops, each saying how it was found. A status is what the " \
                  "last sweep saw, so check live state with the provider's own tools. A link marked not confirmed is a " \
                  "suggestion. Never state it as fact, and say it is unconfirmed if you rely on it. It holds only what runs in the " \
                  "environments the caller may read, and a sheet counts the links it leaves out for that reason. " \
                  "On a large map, find_resources searches by name, provider, kind, environment, owner or tag, " \
                  "traverse_resource_map and blast_radius walk the links, and get_resource_links lists one resource's. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          resource: { type: "string", description: "A resource's name, its provider's id or its id on the map, such as web, firefight-prod/main or an id search_map gave. Leave it out for the whole map" }
        }
      )

      # Only what the principal reads. Naming a resource outside it reads as naming nothing, and a link to one is counted, never named.
      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        return respond(overview(workspace, visible, ResourceMap::Resource.environments_visible_to(principal, workspace))) if args[:resource].blank?

        found = ResourceMap::Resource.candidates(visible, workspace, args[:resource], removed: true)
        return refuse(error: ResourceMap::Resource.not_found_words(args[:resource])) if found.empty?

        more = "#{found.size - SHEETS_SHOWN} more share this name, name one by its id on the map" if found.size > SHEETS_SHOWN
        respond({ resources: found.first(SHEETS_SHOWN).map { |resource| sheet(resource, visible, principal: principal) }, more: more }.compact)
      end

      # The whole map one line per resource while it is small enough to read that way, and its numbers once it is not,
      # saying so, since a list cut short would read as the whole map.
      def self.overview(workspace, visible, environments)
        return summary(workspace, visible, environments) if visible.present.limit(MAP_LINES).count >= MAP_LINES

        accounts = visible.present.order(:provider, :account, :kind, :name).group_by { |resource| [ resource.provider, resource.account ] }.map do |(provider, account), grouped|
          { provider: provider, account: account, resources: grouped.map { |resource| line(resource) } }
        end
        { accounts: accounts, connections: connections(workspace, environments) }
      end

      def self.summary(workspace, visible, environments)
        stats = ResourceMap::Stats.new(workspace, within: visible)
        total = stats.total
        top = ResourceMap::Query.new(workspace, within: visible, sort: ResourceMap::Query::SORT_DEPENDENTS).page(limit: MOST_DEPENDED_ON).resources
        {
          overview: "#{ActiveSupport::NumberHelper.number_to_delimited(total)} resources are on the map, too many to list one by one, " \
                    "so these are its numbers. find_resources searches it by name, provider, kind, environment, owner or tag, " \
                    "traverse_resource_map walks what a resource depends on or what depends on it, and blast_radius says what fails with one.",
          resources: total,
          by_provider: stats.counts(ResourceMap::Stats::BY_PROVIDER), by_kind: stats.counts(ResourceMap::Stats::BY_KIND),
          by_environment: stats.counts(ResourceMap::Stats::BY_ENVIRONMENT).transform_keys { |name| name || NO_ENVIRONMENT },
          by_health: stats.counts(ResourceMap::Stats::BY_HEALTH),
          most_depended_on: rows(top, visible),
          connections: connections(workspace, environments)
        }
      end

      # links leaves out the walk two links out, for a reader that walks the map with its own tools.
      def self.sheet(resource, visible, principal:, links: true)
        hidden = resource.links_out_of_reach(visible) if links
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
          key_checks: (key_checks(resource, principal) unless resource.removed_at),
          usual_log_lines: (usual_log_lines(resource, principal) unless resource.removed_at),
          links: (resource.neighborhood(within: visible).map { |link, hop| link_line(link, hop) } if links),
          out_of_reach: (hidden&.positive? ? "#{hidden} more #{'link'.pluralize(hidden)} within two hops #{hidden == 1 ? 'leads' : 'lead'} to resources in environments you cannot read" : nil)
        }.compact
      end

      # The checks worth running first on it, each with the read it runs as, the connection that answers and its normal,
      # or why it cannot run here. run_key_query runs one.
      def self.key_checks(resource, principal)
        reason = ResourceMap::KeyQueries.none_reason(resource.kind)
        return [ reason ] if reason

        ResourceMap::KeyQueries.plans(resource, principal: principal).map do |plan|
          next "#{plan.check.key}: not available here. #{plan.refusal}" unless plan.available?

          read = [ plan.call.spec.tool_name, ("of #{plan.metric}" if plan.metric) ].compact.join(" ")
          normal = plan.baseline&.normal_text
          normal = normal ? "Normal: #{normal}." : ("No normal read yet." if plan.check.metric?)
          [ "#{plan.check.key} (#{plan.check.label}): #{read} through #{plan.connection}.", normal ].compact.join(" ")
        end
      end

      # The kinds of line it printed most in the last week, or why none are known.
      def self.usual_log_lines(resource, principal)
        lines = resource.log_templates.this_week.most_lines_first.limit(ResourceMap::LogTemplate::SHOWN).map(&:line)
        lines.presence || [ ResourceMap::LogTemplate.missing_reason(resource, principal) ]
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
        "#{link.sentence} (#{how_found(link)}#{', two links away' if hop > 1})#{": #{link.note}" if link.note.present?}"
      end

      # How a link was found, with the settings it was found in by name, never their values.
      def self.how_found(link)
        settings = "#{link.from_resource.name}'s #{link.variables.to_sentence} #{'setting'.pluralize(link.variables.size)}" if link.variables.any?
        found = case link.origin
        when ResourceMap::ORIGIN_DECLARED then "declared by #{link.integration_environment&.integration&.name || 'a provider'}"
        when ResourceMap::ORIGIN_MATCHED
          return "matched from #{settings}, which #{link.variables.one? ? 'names' : 'name'} its address" if settings && link.integration_environment.nil?

          "matched from what #{link.integration_environment&.integration&.name || 'the providers'} report#{'s' if link.integration_environment}"
        when ResourceMap::ORIGIN_PERSON then "added by a person"
        when ResourceMap::ORIGIN_INFERRED
          link.confirmed_at ? "suggested by Firefight, confirmed by a person" : "suggested by Firefight, #{link.certainty}, not confirmed: #{link.clues.join('. ')}"
        else link.confirmed_at ? "suggested by Halon, confirmed by a person" : "suggested by Halon, not confirmed"
        end
        settings ? "#{found}, from #{settings}" : found
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
