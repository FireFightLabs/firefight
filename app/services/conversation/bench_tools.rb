# The tools the bench's scenarios share, kept in step with what a chat is offered live. A shared tool marked live in
# config/halon_bench/_tools.yml is one of Firefight's own tools, a capability or the chat's own, and its description,
# parameters and whether it asks first are read from its definition here, so a tool change can never leave the bench
# offering the old one. halon:bench_tools writes them back, and a test fails naming the tool when they differ.
module Conversation::BenchTools
  # What is compared and refreshed. How a tool reads, whose it is and what it answers by default are the bench's own.
  LIVE_FIELDS = %w[description parameters confirms].freeze

  HEADER = <<~TEXT.freeze
    # Tools many bench scenarios offer, described once. A scenario lists one by name under tools, or describes its own.
    # Each answers only from the scenario's record, so nothing here reaches a real system. A tool marked live is one a
    # chat is offered today: its description, parameters and whether it asks first are copied from its definition by
    # bin/rails halon:bench_tools, and a test fails when they drift. The rest are written here: connection tools such
    # as northflank_api_request, search_handbook, and open_tools, whose list of groups depends on the workspace and on
    # who asks. See Conversation::BenchCase for each field.

  TEXT

  module_function

  # Each live tool by name, as a member of an empty workspace is offered it, built in a transaction that is rolled back
  # so nothing is left behind.
  def live
    found = {}
    ActiveRecord::Base.transaction(requires_new: true) do
      turn = probe_turn
      chat_tools(turn).each { |tool| found[tool.name.to_s] = definition(tool.description, tool.parameters_schema, tool.requires_approval?) }
      Integrations::Capabilities::SPECS.each_value do |spec|
        found[spec.tool_name] = definition(spec.description, Integrations::Capabilities.schema(spec, []), spec.writes)
      end
      found[ResourceMap::Timeline::TOOL_NAME] = definition(ResourceMap::Timeline::DESCRIPTION, ResourceMap::Timeline::SCHEMA, false)
      Mcp::Tools.all.each do |tool_class|
        action = Ability::Action.lookup(Ability::Action.system_key(*tool_class.authorization(turn.workspace, {})), turn.workspace)
        tool = Chat::Tools::Firefight.new(turn, tool_class, action)
        found[tool.name.to_s] ||= definition(tool.description, tool_class.schema_for(turn.workspace), tool.requires_approval?)
      end
      raise ActiveRecord::Rollback
    end
    found
  end

  # The shared tools marked live whose snapshot differs from their definition, each with the fields that differ, and
  # those no longer offered at all.
  def drift(snapshot = Conversation::BenchCase.shared_tools, offered = live)
    snapshot.select { |_name, data| data["live"] }.filter_map do |name, data|
      now = offered[name]
      next [ name, [ "no longer offered" ] ] unless now

      differing = LIVE_FIELDS.reject { |field| comparable(data[field], field) == comparable(now[field], field) }
      [ name, differing ] if differing.any?
    end.to_h
  end

  # Writes each live tool's fields into the snapshot, keeping everything the bench sets itself. Returns the names
  # it changed.
  def refresh!(path = Conversation::BenchCase::SHARED_TOOLS)
    snapshot = YAML.safe_load_file(path)
    offered = live
    changed = drift(snapshot.to_h { |name, data| [ name, data ] }, offered).keys
    refreshed = snapshot.to_h do |name, data|
      next [ name, data ] unless data["live"] && offered[name]

      [ name, data.merge(offered[name].slice(*LIVE_FIELDS)).compact ]
    end
    File.write(path, HEADER + refreshed.to_yaml(line_width: 140).delete_prefix("---\n"))
    changed
  end

  def definition(description, parameters, confirms)
    { "description" => description.to_s, "parameters" => cleaned(parameters), "confirms" => confirms ? true : nil }
  end

  # A schema as the bench offers it: no $schema line, and no intent, which the bench adds itself to a tool that asks.
  def cleaned(parameters)
    schema = JSON.parse(parameters.to_json).except("$schema")
    schema["properties"] = schema["properties"].to_h.except(Chat::Tools::INTENT_ARG)
    schema["required"] = Array(schema["required"]) - [ Chat::Tools::INTENT_ARG ] if schema.key?("required")
    schema
  end

  def comparable(value, field)
    field == "confirms" ? value == true : JSON.parse(value.to_json)
  end

  def chat_tools(turn)
    Conversation::Tools.for(turn, offer: ->(_tools) { }) +
      [ Chat::Tools::Terminal.new(turn), Chat::Tools::OutsideCheck.new(turn), Chat::Tools::Helpers.new(turn, share: nil) ]
  end

  def probe_turn
    workspace = Workspace.create!(name: "Bench tools")
    user = User.create!(email: "bench-tools-#{SecureRandom.hex(6)}@example.invalid", name: "Bench tools")
    member = WorkspaceMembership.create!(workspace: workspace, user: user, role: :member, joined_at: Time.current)
    Conversation::Turn.new(Conversation.start_personal!(workspace: workspace, member: member), asker: member)
  end
end
