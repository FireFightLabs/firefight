module Integrations
  # Finds the one row a person or Halon named, in a list a native pack read from its provider: by its id first, then by
  # a name only one row has, whatever the case. A name two rows share is refused with each one's id, so the caller names
  # it by id rather than Firefight picking one.
  module Named
    # A name more than one row has, with the ids to choose from in the message.
    class Ambiguous < NativePack::Error; end

    # id and name read a row's id and name, each a key (a symbol or string) or a lambda. provider is the provider's name
    # as a person reads it. describe says how each shared row is named in the refusal, its id unless given. connection is
    # the environment row the list was read through, so the refusal names the connection as a person tells it apart and
    # each row's id on the map where the map has it, which is how a name several resources share is named elsewhere.
    # Answers the row, or nil when nothing has that id or name or the reference is empty.
    def self.find(list, reference, id:, name:, provider:, describe: nil, connection: nil)
      wanted = reference.to_s.strip.downcase
      return if wanted.empty?

      rows = Array(list)
      by_id = rows.find { |row| read(row, id).to_s.downcase == wanted }
      return by_id if by_id

      matches = rows.select { |row| read(row, name).to_s.downcase == wanted }
      return matches.first unless matches.many?

      on_map = map_ids(connection, matches.map { |row| read(row, id).to_s })
      choices = matches.map do |row|
        shown = describe ? describe.call(row) : read(row, id).to_s
        mapped = on_map[read(row, id).to_s]
        mapped ? "#{shown} (map id #{mapped})" : shown
      end
      shown_as = connection&.integration&.display_name
      place = shown_as && !shown_as.casecmp?(provider.to_s) ? " in #{shown_as}" : ""
      raise Ambiguous, Sentence.join("More than one #{provider} resource#{place} is called #{reference.to_s.strip}", choices.join(", "), after: "Name it by its id")
    end

    # The map's own id for each of these provider ids that the connection reports, by provider id.
    def self.map_ids(connection, ids)
      return {} unless connection

      ResourceMap::Resource.present.where(workspace_id: connection.integration.workspace_id, external_id: ids)
                           .where("resource_map_resources.integration_environment_id = :row OR resource_map_resources.sightings ? :row", row: connection.id.to_s)
                           .pluck(:external_id, :id).to_h
    end

    def self.read(row, field)
      return field.call(row) if field.respond_to?(:call)

      row.is_a?(Hash) ? row[field] || row[field.to_s] : row.public_send(field)
    end
    private_class_method :read, :map_ids
  end
end
