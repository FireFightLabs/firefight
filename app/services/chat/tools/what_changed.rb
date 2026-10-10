# what_changed: one list of what changed around a resource, a service or the workspace (ResourceMap::Timeline), with
# each resource's runs read live through the run history capability, so each read is authorized, approved, ledgered and
# replayed as the provider's own action, exactly as run_history would be. The list itself is a read of the map, a step
# of its own that a finding can cite.
class Chat::Tools::WhatChanged < RubyLLM::Tool
  NAME = ResourceMap::Timeline::TOOL_NAME

  # history is [spec, tools that could answer, tools this agent may run] for run history, or nil when no connection
  # answers it, in which case the list holds what Firefight recorded alone.
  def initialize(agent_run, history)
    super()
    @agent_run = agent_run
    @spec, @able, @callable = history
  end

  def name = NAME

  def description = ResourceMap::Timeline::DESCRIPTION

  # The same schema an outside agent is handed over MCP.
  def parameters_schema = ResourceMap::Timeline::SCHEMA

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    subject = ResourceMap::Timeline.subject(@agent_run.workspace, @agent_run.acting_principal, given)
    return refused(tool_call, subject) if subject.is_a?(String)

    from, to = ResourceMap::Timeline.window(given)
    timeline = ResourceMap::Timeline.new(workspace: @agent_run.workspace, principal: @agent_run.acting_principal, subject: subject, from: from, to: to)
    live, read = runs(timeline)
    listed = @agent_run.tool_call(action_key: Ability::Action::MAP_READ, params: given, tool_name: name, label: "What changed for #{subject.described}") do
      timeline.text(live: live, read: read)
    end
    Chat::Tools.hand_over(@agent_run, name, listed)
  rescue ArgumentError => error
    refused(tool_call, error.message)
  rescue AbilityGateway::Denied => denied
    refused(tool_call, @agent_run.refusal(denied.action_key))
  rescue AbilityGateway::PendingApproval
    Chat::Tools.waiting_for_approval(Ability::Action::MAP_READ)
  end

  private

  # Each read is its own step, never this call's, so one resource that cannot be read leaves the list standing.
  def runs(timeline)
    targets = ResourceMap::WhatChanged.targets(timeline)
    return [ [], [] ] if targets.empty?
    return [ [], [ "No connection you may use reads runs, so deploys and runs are only those the map saw." ] ] unless @spec && @callable.any?

    targets.each_with_object([ [], [] ]) do |resource, (live, read)|
      capability = Chat::Tools::Capability.new(@agent_run, @spec, @able, callable: @callable)
      said = capability.call(**ResourceMap::WhatChanged.arguments(resource).symbolize_keys)
      answered = capability.answered
      found = answered && ResourceMap::WhatChanged.entries(resource, answered.result, through: answered.call.environment_row.integration.display_name)
      found ? live.concat(found) : read << ResourceMap::WhatChanged.unread(resource, said)
    end
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end
