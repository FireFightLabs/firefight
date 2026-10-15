# What a runbook's editor offers to pick from: every tool Halon can be asked to run a step with, by the name Halon calls
# it and grouped as a person finds it, each with the fields its parameters make, the reads a watch can make, and what
# is on the map to watch. Built from the same schemas a chat hands the model, so a step saved here runs as written.
module Chat::Tools::Choices
  KIND_TEXT = ToolField::KIND_TEXT
  KIND_NUMBER = ToolField::KIND_NUMBER
  KIND_SELECT = ToolField::KIND_SELECT
  KIND_TOGGLE = ToolField::KIND_TOGGLE
  KIND_LIST = ToolField::KIND_LIST
  KIND_KEPT = ToolField::KIND_KEPT
  KIND_RESOURCE = ToolField::KIND_RESOURCE
  KINDS = ToolField::KINDS

  # Who a group belongs to: Firefight's own tools, the capabilities that answer for anything on the map, or a connection.
  GROUP_RESOURCES = "Anything on the resource map".freeze
  RESOURCE_LIMIT = 500

  Field = ToolField::Field
  # reads is whether a watch can read with it: it only reads, or a guard keeps it to reads in a watch.
  # watch_fields are what a watch reads with instead, when a guard keeps the tool to reads through arguments of its own.
  # read_only is whether every call only reads, which a workflow step's Reads or Changes says, and action_key is the
  # gateway action a call makes, nil when the arguments decide it, such as a capability picking a connection.
  # status_page marks a tool of a connection whose provider hosts its customers' status pages.
  Choice = Data.define(:name, :group, :description, :fields, :reads, :watch_fields, :read_only, :action_key, :status_page) do
    def initialize(watch_fields: nil, read_only: nil, action_key: nil, status_page: false, **) = super
  end
  Read = Data.define(:name, :label, :history)
  Place = Data.define(:name, :kind)

  module_function

  def tools(workspace)
    firefight(workspace) + capabilities(workspace) + connections(workspace)
  end

  def firefight(workspace)
    titles = Chat::Tools::Groups::FIREFIGHT.to_h { |group| [ group.key, group.title ] }
    Mcp::Tools.available_in(workspace).reject { |tool_class| Chat::Tools::Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s) }.map do |tool_class|
      name = tool_class.name_value.to_s
      Choice.new(name: name, group: titles.fetch(Chat::Tools::Groups.of_firefight_tool(name), "Firefight"),
                 description: Chat::Tools.clean(tool_class.description_value, Chat::Tools::ONE_LINE),
                 fields: fields(tool_class.schema_for(workspace).deep_stringify_keys), reads: tool_class.annotations_value&.read_only_hint == true,
                 read_only: tool_class.annotations_value&.read_only_hint == true, action_key: firefight_action_key(tool_class, workspace))
    end
  end

  # What a call of one of Firefight's own tools is authorized as, when that does not depend on its arguments.
  def firefight_action_key(tool_class, workspace)
    resource, action = tool_class.authorization(workspace, {})
    Ability::Action.system_key(resource, action)
  rescue StandardError, NotImplementedError
    nil
  end

  def capabilities(workspace)
    Integrations::Capabilities.offered(workspace).map do |spec, tools|
      schema = Integrations::Capabilities.schema(spec, Integrations::Capabilities.connection_choices(workspace, spec, tools))
      Choice.new(name: spec.tool_name, group: GROUP_RESOURCES, description: Chat::Tools.clean(spec.description, Chat::Tools::ONE_LINE),
                 fields: fields(schema).map { |field| field.key == Integrations::Capabilities::RESOURCE_ARG ? field.with(kind: KIND_RESOURCE) : field },
                 reads: !spec.writes, read_only: !spec.writes)
    end
  end

  # Each connection's environments are read once for all its tools, which every tool's schema names.
  def connections(workspace)
    tools = workspace.switched_on_tools
                     .reject { |tool| Integrations::Capabilities.wrapped?(tool) || Integrations::Capabilities.tool_names.include?(tool.model_facing_name) }
    rows = tools.map(&:integration).uniq.index_with(&:offered_environment_rows)
    tools.map do |tool|
      Choice.new(name: tool.model_facing_name, group: tool.integration.display_name,
                 description: Chat::Tools.clean(tool.description, Chat::Tools::ONE_LINE), fields: fields(tool.offered_schema(rows.fetch(tool.integration))),
                 reads: tool.read_only? || Integrations::ReadGuards.for(tool).present?, watch_fields: watched_fields(tool),
                 read_only: tool.read_only?, action_key: tool.action_key, status_page: IntegrationProvider.find(tool.integration.provider)&.holds_status_pages || false)
    end
  end

  # A tool a guard keeps to reads in a watch is read through the guard's own arguments there, when the guard has some,
  # so a watch item is written in them. A step of a runbook keeps the tool's own. nil when they are the same.
  def watched_fields(tool)
    schema = !tool.read_only? && Integrations::ReadGuards.for(tool)&.schema
    schema ? fields(schema) : nil
  end

  # The reads a watch can check with, run history first since it follows a run by its status.
  def reads
    Integrations::Capabilities::SPECS.values.reject(&:writes).sort_by { |spec| spec.key == Integrations::Capabilities::HISTORY ? 0 : 1 }.map do |spec|
      Read.new(name: spec.tool_name, label: Chat::Watch::Step.read_label(spec), history: spec.key == Integrations::Capabilities::HISTORY)
    end
  end

  # What a watch can follow, as the map names it for this person.
  def places(workspace, member)
    ResourceMap::Resource.visible_to(member, workspace).present.order(:name).limit(RESOURCE_LIMIT).pluck(:name, :kind).uniq
                         .map { |name, kind| Place.new(name: name, kind: kind) }
  end

  def fields(schema)
    required = Array(schema["required"]).map(&:to_s)
    schema.fetch("properties", {}).map do |key, property|
      property = property.to_h.stringify_keys
      Field.new(key: key.to_s, kind: kind_of(property), options: Array(property["enum"]).map(&:to_s),
                required: required.include?(key.to_s), description: property["description"].to_s.squish.presence)
    end
  end

  def kind_of(property)
    type = Array(property["type"]).first.to_s
    return KIND_SELECT if property["enum"].present?
    return KIND_TOGGLE if type == "boolean"
    return KIND_NUMBER if %w[integer number].include?(type)
    return KIND_TEXT if type == "string" || type.empty?
    return KIND_LIST if type == "array" && %w[string integer number].include?(property.dig("items", "type").to_s)

    KIND_KEPT
  end
end
