module Integrations
  # Whether a failed call was the provider saying the thing it was asked about is not there, which answers a check rather
  # than breaking it. It is read from what the provider answered, never from what the agent said about it. That is an
  # error marked NotFound, or a remote server's own answer read by the error reader its provider's definition names. Only a
  # call that reads counts, since a change that found nothing to change still did not do what it was asked.
  module Outcomes
    def self.not_found?(tool, arguments, error: nil, said: nil)
      return false unless reads?(tool, arguments)

      error ? not_found_error?(error) : said_not_found?(tool, said)
    end

    # For a run, where every call only reads, so the error alone settles it.
    def self.not_found_error?(error) = error.is_a?(NotFound)

    def self.reads?(tool, arguments) = tool.read_only? || ReadGuards.reads?(tool, arguments)

    def self.said_not_found?(tool, said)
      reader = Provider.for(tool.integration.provider).error_reader
      reader.present? && reader.not_found?(said.to_s)
    end
    private_class_method :said_not_found?
  end
end
