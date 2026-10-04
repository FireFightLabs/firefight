module Integrations
  # Finds the one row a person or Halon named, in a list a native pack read from its provider: by its id first, then by
  # a name only one row has, whatever the case. A name two rows share is refused with each one's id, so the caller names
  # it by id rather than Firefight picking one.
  module Named
    # A name more than one row has, with the ids to choose from in the message.
    class Ambiguous < NativePack::Error; end

    # id and name read a row's id and name, each a key (a symbol or string) or a lambda. provider is the provider's name
    # as a person reads it. describe says how each shared row is named in the refusal, its id unless given. Answers the
    # row, or nil when nothing has that id or name or the reference is empty.
    def self.find(list, reference, id:, name:, provider:, describe: nil)
      wanted = reference.to_s.strip.downcase
      return if wanted.empty?

      rows = Array(list)
      by_id = rows.find { |row| read(row, id).to_s.downcase == wanted }
      return by_id if by_id

      matches = rows.select { |row| read(row, name).to_s.downcase == wanted }
      return matches.first unless matches.many?

      choices = matches.map { |row| describe ? describe.call(row) : read(row, id).to_s }
      raise Ambiguous, Sentence.join("More than one #{provider} resource is called #{reference.to_s.strip}", choices.join(", "), after: "Name it by its id")
    end

    def self.read(row, field)
      return field.call(row) if field.respond_to?(:call)

      row.is_a?(Hash) ? row[field] || row[field.to_s] : row.public_send(field)
    end
    private_class_method :read
  end
end
