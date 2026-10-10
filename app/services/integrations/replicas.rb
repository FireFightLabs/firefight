module Integrations
  # Seen in a real chat, a database's server read from a replica by default, Halon's first read went there and timed
  # out, and only then did it ask for the primary. Halon reads the primary first, since it is current and every branch
  # has one, and a replica only as a fallback, when the primary was slow or refused. A provider names the argument and
  # the value that pick the primary in its definition (Provider#primary_reads).
  module Replicas
    DESCRIPTION = "Leave this out to read the primary, which is current. Ask for a replica only as a fallback, after the " \
                  "primary was slow or refused, and then say the answer came from a replica, which may lag behind it.".freeze

    # The tool's schema with the description of its replica argument saying so, as Halon is offered it.
    def self.offered(tool, schema)
      argument, = primary_of(tool)
      return schema unless argument && schema.dig("properties", argument)

      schema.deep_merge("properties" => { argument => { "description" => DESCRIPTION } })
    end

    # The arguments of a call that does not say where to read, sent to the primary.
    def self.primary_first(tool, arguments)
      argument, value = primary_of(tool)
      return arguments if argument.nil? || arguments.key?(argument)

      arguments.merge(argument => value)
    end

    def self.primary_of(tool) = Provider.for(tool.integration.provider).primary_reads[tool.name]&.first
    private_class_method :primary_of
  end
end
