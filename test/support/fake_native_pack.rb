# The canonical native pack for tests: one read tool per return shape plus a
# write tool. Stub Integrations::NativePacks.for to return it (or a subclass
# for behavior-specific cases like failing health checks).
class FakeNativePack < Integrations::NativePack
  tool :echo_text, description: "Echoes text back",
                   params_schema: { "type" => "object", "properties" => { "text" => { "type" => "string" } } },
                   read_only: true
  tool :structured, description: "Already MCP-shaped", params_schema: { "type" => "object" }, read_only: true
  tool :data_result, description: "Returns a hash", params_schema: { "type" => "object" }, read_only: true
  tool :write_thing, description: "Writes a thing", params_schema: { "type" => "object" }, read_only: false

  def echo_text(environment_row:, arguments:)
    "echo: #{arguments['text']}"
  end

  def structured(environment_row:, arguments:)
    { "content" => [ { "type" => "text", "text" => "as-is" } ], "isError" => false }
  end

  def data_result(environment_row:, arguments:)
    { "rows" => [ 1, 2 ] }
  end

  def write_thing(environment_row:, arguments:)
    "written"
  end
end
