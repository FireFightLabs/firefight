module Integrations
  # What every provider's pager shares (Integrations::Paging). A pager reaches its provider's API with its own client,
  # and each call is authorized as one of the connection's tools, the one that makes the same change, so a grant, a
  # tool switched off, an approval rule and the activity log treat it as that tool.
  class Pager
    attr_reader :integration

    def initialize(integration, environment_row, tools, &authorize)
      @integration = integration
      @environment_row = environment_row
      @tools = tools
      @authorize = authorize
    end

    private

    def settings = @settings ||= ConnectionSettings.of(@environment_row)

    # Runs the block as a call of the tool, authorized by whoever is acting. A tool that is off is Failed, since the
    # change it makes is not one the connection allows. what says what the call does, for that sentence.
    def through(tool_name, arguments, what)
      tool = @tools[tool_name]
      raise Paging::Failed, "#{@integration.name}'s #{tool_name} is switched off, so Firefight cannot #{what}." unless tool

      @authorize.call(tool, arguments) { yield }
    end
  end
end
