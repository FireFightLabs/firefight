module Integrations
  # A connection whose provider names what it reads by a scope field (IntegrationProvider::ConnectField, scope), such as
  # Northflank's projects or Render's workspaces, reaches one, several or every one its credential can read. When it
  # reaches several, each call reaches exactly one, named under the field's key: by the caller, or found from the resource
  # the call names on the map, which lives in one. A call that could reach more than one is refused with the choices,
  # never sent to one picked for it.
  module Scopes
    # A scope that was asked for and is not one the connection reaches, or a resource that is in more than one.
    class Unresolved < NativePack::Error; end

    # The parameter a connection's tools take to name the scope, by the field's key, or nil when none of its rows reaches
    # more than one. It lists the scopes its rows reach as last listed, so a model picks one that exists.
    def self.argument(integration)
      every = integration.integration_environments.select(&:enabled).map { |row| ConnectionSettings.of(row) }
      field = every.first&.scope_field
      return unless field && every.any?(&:several_scopes?)

      known = every.flat_map(&:known_scopes).uniq
      named = known.map { |id| [ id, every.map { |settings| settings.scope_name(id) }.find { |name| name != id } ] }
      listed = named.map { |id, name| name ? "#{id} (#{name})" : id }
      property = { "type" => "string",
                   "description" => "Which #{field.one} to run in, by its id#{": #{listed.join(', ')}" if listed.any?}. Leave it out when you " \
                                    "name a resource on the map, which is in one #{field.one} and says which." }
      property["enum"] = known if known.any?
      { field.key => property }
    end

    # The arguments with the scope the call reaches under the field's key. One the caller gave is kept when the
    # connection reaches it. Otherwise, when the connection reaches several, it is the one the resources the call names
    # live in on the map (NativePack.scope_references). Raises Unresolved for a scope the connection does not reach, or a
    # resource that is in more than one. Left as they are when nothing says, for the pack to refuse or read every scope.
    def self.resolved(environment_row, arguments)
      return arguments unless environment_row

      settings = ConnectionSettings.of(environment_row)
      field = settings.scope_field
      return arguments unless field && environment_row.integration.native?

      given = arguments[field.key].to_s.strip
      return arguments.merge(field.key => given) if given.present? && reaches?(settings, given)
      raise Unresolved, outside(settings, given) if given.present?
      return arguments unless settings.several_scopes?

      pack = NativePack.for(settings.provider_key)
      return arguments unless pack

      found = on_map(environment_row, pack.scope_references(arguments)).sort_by { |scope, _names| settings.known_scopes.index(scope) || settings.known_scopes.size }.to_h
      return arguments if found.empty?
      return arguments.merge(field.key => found.keys.first) if found.one?

      raise Unresolved, "#{found.values.flatten.uniq.to_sentence} #{found.values.flatten.uniq.one? ? 'is' : 'are'} in more than one " \
                        "#{field.one} #{environment_row.integration.display_name} reaches: #{found.keys.to_sentence}. Name the #{field.one} " \
                        "with #{field.key}."
    end

    # The scope a call reaches as resolved would name it, or nil when it names none or cannot be resolved, for a label put
    # to a person before the call runs.
    def self.of_call(environment_row, arguments)
      field = environment_row && ConnectionSettings.of(environment_row).scope_field
      field && resolved(environment_row, arguments.to_h)[field.key].presence
    rescue Integrations::Error
      nil
    end

    # A capability's arguments with the scope its resource lives in, for a connection that reaches several, so a change
    # only ever reaches the scope the resource is in.
    def self.for_resource(environment_row, resource, arguments)
      settings = ConnectionSettings.of(environment_row)
      scope = resource.details.to_h[ResourceMap::SCOPE].presence
      return arguments unless settings.scope_field && scope && resource.provider == settings.provider_key && settings.several_scopes?

      arguments.merge(settings.scope_field.key => scope)
    end

    # What a read of one scope found, with each of the provider's own resources marked with the scope it lives in.
    # Hostnames and repositories are the same whichever scope names them, so they stay unmarked.
    def self.marked(snapshot, settings, scope)
      named = settings.scope_name(scope)
      marks = { ResourceMap::SCOPE => scope, ResourceMap::SCOPE_NAME => (named unless named == scope) }.compact
      snapshot.with(resources: snapshot.resources.map { |found| found.provider == settings.provider_key ? found.with(details: found.details.merge(marks)) : found })
    end

    # The resources by the scope each lives in. A connection that reaches one reads them all there. One that reaches
    # several reads each in the scope the map marked it with, and one no sweep marked yet waits for the next.
    def self.grouped(settings, resources)
      return { settings.scopes.first => resources } unless settings.several_scopes?

      resources.group_by { |resource| resource.details.to_h[ResourceMap::SCOPE].presence }.except(nil)
    end

    # The scopes the resources named by references live in on the connection's map, each with the names found there.
    def self.on_map(environment_row, references)
      wanted = Array(references).filter_map { |reference| reference.to_s.strip.downcase.presence }.uniq
      return {} if wanted.empty?

      ResourceMap::Resource.present.where(workspace_id: environment_row.integration.workspace_id, provider: environment_row.integration.provider)
                           .where("resource_map_resources.integration_environment_id = :row OR resource_map_resources.sightings ? :row", row: environment_row.id.to_s)
                           .where("lower(resource_map_resources.name) IN (:wanted) OR lower(resource_map_resources.external_id) IN (:wanted)", wanted: wanted)
                           .pluck(:name, Arel.sql("resource_map_resources.details ->> '#{ResourceMap::SCOPE}'"))
                           .select { |_name, scope| scope.present? }.group_by(&:last).transform_values { |pairs| pairs.map(&:first).uniq }
    end

    def self.reaches?(settings, scope)
      settings.known_scopes.include?(scope) || (settings.all_scopes? && settings.scopes.include?(scope))
    end

    def self.outside(settings, given)
      field = settings.scope_field
      reached = settings.known_scopes
      "#{settings.display_name} does not reach #{field.one} #{given}." +
        (reached.any? ? " It reaches #{field.reach_words(reached)}." : "")
    end
    private_class_method :on_map, :reaches?, :outside
  end
end
