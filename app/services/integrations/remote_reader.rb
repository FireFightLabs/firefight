module Integrations
  # What Firefight reads through a remote server with its own fixed reads, never a script a model wrote. A provider's
  # map reader (map), baseline reader (baselines) and health probe (check!) are each one. A reader calls only the
  # connection's tools an admin switched on, and McpExecutor records each call, under the map sweep for the map and
  # baselines and under the health check for a probe. A tool that is off answers nil and is never called, so what it
  # would have read is a gap.
  #
  # The contract, for a subclass:
  #   map                         a ResourceMap::Snapshot
  #   baselines(resources, window) ResourceMap::Baseline::Found readings, or nil when the tool that reads them is off
  #   check!                       raises Integrations::Error with the provider's words when the server cannot reach the
  #                                account behind it, and answers what it learned to keep (a hash), or nil to keep
  #                                what it learned before
  class RemoteReader
    # A probe's refusal, with the provider's own words, which the connection shows as why it is failing.
    class Refused < Integrations::Error; end

    attr_reader :settings

    # settings is the connection's ConnectionSettings and tools its switched on tools by name. call_tool runs one of
    # them and answers what it returned, or nil when it is off.
    def initialize(settings = nil, tools = {}, &call_tool)
      @settings = settings
      @tools = tools
      @call_tool = call_tool
    end

    # A switched on tool's answer, or nil when it is off. reads says in words what the call read, for the activity log.
    def call(name, arguments = {}, reads = nil) = @call_tool.call(name, arguments, reads)

    # What a reader could not read, for the map's gaps (ResourceMap::Gap).
    def gaps = @gaps ||= []

    # Records what could not be read and the kinds of resource it would have put on the map, which the sweep then takes
    # nothing of as gone. kinds is empty only for what holds no resource back. settings marks a gap in where stores are
    # reached or where settings point, so those read before are kept. Answers nil.
    def gap(words, kinds:, settings: false)
      gaps << ResourceMap::Gap.new(text: words, kinds: kinds, settings: settings)
      nil
    end

    # A tool's answer read as data, a list or an object, past the line linking to its page. A tool that is off, a
    # refusal or an answer that is not data is a gap naming kinds, what the list holds, and answers nil, so a map reader
    # goes on with the rest.
    def listing(tool, what, arguments = {}, kinds:)
      result = call(tool, arguments)
      return gap("#{tool} is switched off for #{provider_name}, so the #{what} are not on the map.", kinds: kinds) if result.nil?
      if result["isError"]
        return gap(Sentence.join("#{provider_name} refused to list the #{what}", Capabilities::Answers.text(result).truncate(200)), kinds: kinds)
      end

      Capabilities::Answers.data(result) || gap("#{provider_name} answered the #{what} with something that is not JSON.", kinds: kinds)
    end

    # The objects in a listing's answer, a bare list or one under key. Any other shape is a gap naming kinds, never an
    # empty list, so what the reader could not read is not taken as gone. Answers the objects, or nil.
    def objects(data, what, kinds:, key:)
      return nil if data.nil?

      list = data.is_a?(Hash) ? data[key] : data
      return list if list.is_a?(Array) && list.all?(Hash)

      gap("#{provider_name} answered the #{what} in a shape Firefight does not read.", kinds: kinds)
    end

    # Raises Refused with the provider's own words when a tool's answer is an error, for a health probe.
    def refused!(tool, result)
      return result unless result&.dig("isError")

      raise Refused, Sentence.join("#{provider_name} refused #{tool}", Capabilities::Answers.text(result).truncate(300))
    end

    # The provider's name as a person reads it, the reader's NAME or else its registry entry's.
    def provider_name
      return self.class::NAME if self.class.const_defined?(:NAME)

      IntegrationProvider.find(settings&.provider_key.to_s)&.name || self.class.name.demodulize
    end


    def on?(name) = @tools.key?(name)

    # The workspace whose keys digest the addresses a reader reports (ResourceMap::Endpoint), nil without a connection.
    def workspace = settings&.workspace

    # The parameters the connected tool reports, for a provider whose server publishes them and whose docs do not.
    def parameters(name) = @tools[name]&.params_schema.to_h.fetch("properties", {})
  end
end
