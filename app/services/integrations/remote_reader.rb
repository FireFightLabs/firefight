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

    def on?(name) = @tools.key?(name)

    # The parameters the connected tool reports, for a provider whose server publishes them and whose docs do not.
    def parameters(name) = @tools[name]&.params_schema.to_h.fetch("properties", {})
  end
end
