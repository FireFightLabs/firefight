module Integrations
  # A secret that moves from a person or one connection to another connection without passing through Halon. A tool that
  # sets one answers with an entry naming where it goes, and the value is typed by the person in Firefight's dashboard,
  # or read live from another connection through a reference when the call names one. A tool that makes a credential
  # answers with a reference to it, which the person reveals in the dashboard. A reference names where the value lives,
  # never the value, so it can be shown to the model, and nothing here stores a value.
  #
  # A pack plays its part through two methods. fill_secret(environment_row:, target:, value:) sends a value where an
  # entry's target says and answers what it did, and secret_value(environment_row:, path:) reads the value a reference's
  # path names. Integration::SecretHandoff reaches each only after the gateway allowed the person the tool that asked.
  module SecretHandoffs
    ENTRY = "secret_entry".freeze
    REVEAL = "secret_reveal".freeze
    VALUE_FROM = "value_from".freeze
    TARGET = "target".freeze
    TITLE = "title".freeze
    REFERENCE = "reference".freeze
    PREFIX = "secret".freeze
    # GitHub's own limit for a secret, and more than any credential a provider makes.
    VALUE_LIMIT = 48 * 1024

    # A reference that names nothing this workspace can read, or a value that cannot be sent. Its message says why.
    class Unresolved < Error; end

    Reference = Data.define(:integration_id, :catalog_entry_id, :tool_name, :path)

    VALUE_FROM_PARAM = {
      "type" => "string",
      "description" => "A secret reference another tool gave, such as secret:..., whose value Firefight reads itself and sets, " \
                       "so it is never shown. Leave it out and the person types the value in Firefight instead (optional)"
    }.freeze

    # The words a pack answers with when a value waits for a person. A chat replaces them with where the field is.
    NOT_IN_A_CHAT = "Nothing was set. The value is typed by a person in a secure field in Firefight's dashboard, which only a " \
                    "call made in a Halon chat opens. Ask in a Halon chat, or pass value_from with a secret reference.".freeze

    # A tool's answer asking for a value. target says where it goes, in the pack's own words, and title names it for the
    # person.
    def self.entry_result(text, target:, title:, value_from: nil, link: nil)
      result = Telemetry.result(text, link: link)
      result.merge(Telemetry::STRUCTURED => { ENTRY => { TARGET => target, TITLE => title, VALUE_FROM => value_from.presence }.compact })
    end

    # A tool's answer naming a credential it made, for the person to reveal.
    def self.reveal_result(text, reference:, title:, link: nil)
      result = Telemetry.result(text, link: link)
      result.merge(Telemetry::STRUCTURED => { REVEAL => { REFERENCE => reference, TITLE => title } })
    end

    def self.entry_of(result) = result.is_a?(Hash) ? result.dig(Telemetry::STRUCTURED, ENTRY) : nil

    def self.reveal_of(result) = result.is_a?(Hash) ? result.dig(Telemetry::STRUCTURED, REVEAL) : nil

    # Where a value lives, which is the connection, its environment, the tool that made it and the pack's own path to it.
    def self.reference_for(environment_row, tool_name, path)
      [ PREFIX, environment_row.integration_id, environment_row.catalog_entry_id, tool_name, path ].join(":")
    end

    def self.parse(text)
      prefix, integration_id, catalog_entry_id, tool_name, path = text.to_s.strip.split(":", 5)
      unless prefix == PREFIX && [ integration_id, tool_name, path ].all?(&:present?)
        raise Unresolved, "#{text.to_s.truncate(80).inspect} is not a secret reference. Pass the reference a tool gave, as it gave it."
      end

      Reference.new(integration_id: integration_id, catalog_entry_id: catalog_entry_id.presence, tool_name: tool_name, path: path)
    end

    # Raises with why a value cannot be sent.
    def self.checked!(value)
      raise Unresolved, "The value is empty." if value.to_s.empty?
      raise Unresolved, "The value is longer than #{VALUE_LIMIT / 1024} KB." if value.to_s.bytesize > VALUE_LIMIT
    end
  end
end
