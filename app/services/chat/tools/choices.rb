# What a runbook's editor offers to pick from: every tool Halon can be asked to run a step with, by the name Halon calls
# it and grouped as a person finds it, each with the fields its parameters make, the reads a watch can make, and what
# is on the map to watch. Built from the same schemas a chat hands the model, so a step saved here runs as written.
module Chat::Tools::Choices
  KIND_TEXT = "text".freeze
  KIND_NUMBER = "number".freeze
  KIND_SELECT = "select".freeze
  KIND_TOGGLE = "toggle".freeze
  # A list of words, written separated by commas.
  KIND_LIST = "list".freeze
  # A shape a form cannot hold, such as an object, which the editor keeps as it was and does not write.
  KIND_KEPT = "kept".freeze
  # Something on the map, picked from what is there.
  KIND_RESOURCE = "resource".freeze
  KINDS = [ KIND_TEXT, KIND_NUMBER, KIND_SELECT, KIND_TOGGLE, KIND_LIST, KIND_KEPT, KIND_RESOURCE ].freeze

  # Who a group belongs to: Firefight's own tools, the capabilities that answer for anything on the map, or a connection.
  GROUP_RESOURCES = "Anything on the resource map".freeze
  RESOURCE_LIMIT = 500

  Field = Data.define(:key, :kind, :options, :required, :description)
  Choice = Data.define(:name, :group, :description, :fields)
  Read = Data.define(:name, :label, :history)
  Place = Data.define(:name, :kind)

  module_function

  def tools(workspace)
    firefight(workspace) + capabilities(workspace) + connections(workspace)
  end

  def firefight(workspace)
    titles = Chat::Tools::Groups::FIREFIGHT.to_h { |group| [ group.key, group.title ] }
    Mcp::Tools.all.reject { |tool_class| Chat::Tools::Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s) }.map do |tool_class|
      name = tool_class.name_value.to_s
      Choice.new(name: name, group: titles.fetch(Chat::Tools::Groups.of_firefight_tool(name), "Firefight"),
                 description: Chat::Tools.clean(tool_class.description_value, Chat::Tools::ONE_LINE),
                 fields: fields(tool_class.schema_for(workspace).deep_stringify_keys))
    end
  end

  def capabilities(workspace)
    Integrations::Capabilities.offered(workspace).map do |spec, tools|
      schema = Integrations::Capabilities.schema(spec, Integrations::Capabilities.connection_choices(workspace, spec, tools))
      Choice.new(name: spec.tool_name, group: GROUP_RESOURCES, description: Chat::Tools.clean(spec.description, Chat::Tools::ONE_LINE),
                 fields: fields(schema).map { |field| field.key == Integrations::Capabilities::RESOURCE_ARG ? field.with(kind: KIND_RESOURCE) : field })
    end
  end

  def connections(workspace)
    Integration::Tool.in_workspace(workspace).includes(:integration).to_a
                     .reject { |tool| Integrations::Capabilities.wrapped?(tool) || Integrations::Capabilities.tool_names.include?(tool.model_facing_name) }
                     .map do |tool|
      Choice.new(name: tool.model_facing_name, group: tool.integration.display_name,
                 description: Chat::Tools.clean(tool.description, Chat::Tools::ONE_LINE), fields: fields(tool.offered_schema))
    end
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
