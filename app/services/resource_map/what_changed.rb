# The live part of what changed (ResourceMap::Timeline): each resource's recent runs, its deploys, builds and CI runs,
# read from the provider that runs it through the run history capability, so they sit in the list beside what Firefight
# holds. Each surface reads them its own way, so the call is authorized, approved and ledgered as the provider's own
# action from where it was asked, and hands each answer here.
module ResourceMap::WhatChanged
  HISTORY = Integrations::Capabilities::HISTORY

  module_function

  # The resources whose runs are read live, those of the subject that a connection holding them reads run history for.
  def targets(timeline)
    timeline.live_targets.select do |resource|
      resource.holders.any? { |row| Integrations::Capabilities.adapter_for(row.integration.provider)&.supports?(HISTORY, resource.kind) }
    end
  end

  # The entries a run history answer holds, or nil when it holds none, such as an error.
  def entries(resource, result, through:)
    runs = Integrations::Capabilities::History.runs_of(result)
    runs&.filter_map { |run| ResourceMap::Timeline.run_entry(resource, run.to_h, through: through) }
  end

  # Why a resource's runs are not in the list, from what its read answered.
  def unread(resource, said)
    reason = said.to_s.lines.map(&:strip).find(&:present?) || "nothing answered"
    "The runs of #{resource.scoped_name} could not be read: #{reason}"
  end

  def arguments(resource) = { Integrations::Capabilities::RESOURCE_ARG => resource.id, "limit" => Integrations::Capabilities::History::LIMIT }

  # The runs of each target read as a person from the dashboard, each authorized as the provider tool run history runs
  # as, answering the entries and the notes on what could not be read.
  def read_as(timeline, principal:)
    targets(timeline).each_with_object([ [], [] ]) do |resource, (live, read)|
      workspace = resource.workspace
      tools = Integrations::Capabilities.callable(workspace, HISTORY, principal)
      call = Integrations::Capabilities.resolve(workspace, HISTORY, arguments(resource), tools, principal: principal)
      result = ResourceMap::KeyQueryRun.ask(call, principal, nil)
      found = entries(resource, result, through: call.environment_row.integration.display_name)
      found ? live.concat(found) : read << unread(resource, ResourceMap::KeyQueryRun.text_of(result))
    rescue Integrations::Capabilities::Unroutable => error
      read << unread(resource, error.message)
    rescue AbilityGateway::Denied
      read << "You may not read the runs of #{resource.scoped_name}. An admin can grant it on the Permissions page."
    rescue AbilityGateway::PendingApproval
      read << "Reading the runs of #{resource.scoped_name} waits for an approval. Read them again once it is approved."
    end
  end
end
