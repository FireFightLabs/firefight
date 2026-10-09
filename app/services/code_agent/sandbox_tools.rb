# start_service for a coding agent: Postgres or Redis inside the sandbox it writes the change in, the way run_tests
# starts them, so it never sets up a database of its own. Each start is in the ledger under the session's workspace,
# and a service the sandbox cannot start is answered in a sentence.
module CodeAgent::SandboxTools
  START = "start_service".freeze

  # Offered only where the change has a box, which its reads and its commands share.
  def self.for(session)
    return [] if session.box_key.blank?

    [
      ::MCP::Tool.define(
        name: START,
        description: "Start a database or cache inside this sandbox for a check that needs one, instead of installing or running " \
                     "one yourself. The sandbox starts #{CodeBox::SERVICES.join(' and ')}. The answer gives the variables that " \
                     "reach it, to set on the command that uses it.",
        input_schema: { type: "object", required: [ "name" ], properties: {
          name: { type: "string", description: "The service, such as #{CodeBox::SERVICES.first}" }
        } }
      ) { |name:, **| CodeAgent::SandboxTools.start(session, name.to_s.strip.downcase) }
    ]
  end

  def self.start(session, name)
    unless CodeBox::SERVICES.include?(name)
      return refusal("The sandbox cannot start #{name.presence || 'that'}. It can start #{CodeBox::SERVICES.join(' and ')}.")
    end

    started = session.start_sandbox_service!(name) { Integrations::CodeReading.start_services(session.box_key, [ name ]) }
    variables = started["env"].to_h.map { |key, value| "#{key}=#{value}" }
    text("#{name} is running in this sandbox. Set these on the command that uses it:\n#{variables.join("\n")}")
  rescue Integrations::Error => error
    refusal("#{name} could not start: #{error.message}")
  end

  def self.text(words) = ::MCP::Tool::Response.new([ { type: "text", text: words } ])

  def self.refusal(words) = ::MCP::Tool::Response.new([ { type: "text", text: words } ], error: true)
end
