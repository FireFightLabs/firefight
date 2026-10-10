# Runs one of a resource's key checks (ResourceMap::KeyQueries) as a person from the map, through the gateway as the
# provider tool it resolves to, as every other surface calls a capability, so grants, approval rules and the ledger see
# the provider's own action.
class ResourceMap::KeyQueryRun
  KEY_QUERIES = ResourceMap::KeyQueries
  CAPABILITIES = KEY_QUERIES::CAPABILITIES

  # What a person who ran a check from the map sees: the headline, the answer's text and charts, whether the provider
  # failed it, or the approval it waits for. refusal is why it did not run at all.
  Outcome = Data.define(:headline, :text, :link, :charts, :failed, :approval_id, :refusal) do
    def initialize(headline: nil, text: nil, link: nil, charts: [], failed: false, approval_id: nil, refusal: nil) = super
  end

  # A chart an answer drew, in the shape a chat's chart has, so the page draws both the same way.
  Chart = Data.define(:id, :tool_call_id, :title, :unit, :step_position, :source_url, :range_start, :range_end, :series)

  def self.call(resource, check, principal:, minutes: KEY_QUERIES::DEFAULT_MINUTES, approval_id: nil)
    workspace = resource.workspace
    tools = CAPABILITIES.callable(workspace, check.capability, principal)
    plan = KEY_QUERIES.plan(resource, check, principal: principal, tools: tools)
    return Outcome.new(refusal: plan.refusal) unless plan.available?

    call = CAPABILITIES.resolve(workspace, check.capability, plan.arguments(minutes), tools, principal: principal)
    answered = call
    result = ask(call, principal, approval_id)
    if call.fallback && !CAPABILITIES.definitive?(result)
      lead = CAPABILITIES.fell_back(call, failure: (text_of(result) if result["isError"] == true))
      answered = call.fallback
      result = ask(call.fallback, principal, approval_id)
    end
    lines = [ lead, text_of(result) ].compact.join("\n").lines(chomp: true)
    links, said = lines.partition { |line| Integrations::Telemetry.link_line?(line) }
    Outcome.new(headline: KEY_QUERIES.headline(check, answered, plan.metric, result), text: said.join("\n"), link: links.first&.split&.last,
                charts: charts_of(result), failed: result["isError"] == true)
  rescue CAPABILITIES::Unroutable => error
    Outcome.new(refusal: error.message)
  rescue AbilityGateway::Denied => denied
    Outcome.new(refusal: "You may not run #{denied.action_key} here. An admin can grant it on the Permissions page.")
  rescue AbilityGateway::PendingApproval => pending
    Outcome.new(approval_id: pending.approval.id,
                refusal: "#{pending.approval.action_key} needs a workspace #{pending.approval.required_role} to approve it first. Run it again once it is approved.")
  end

  # A provider's own error is an answer that failed, as a chat and MCP read it. Shared with what changed on the map
  # (ResourceMap::WhatChanged), which reads runs the same way.
  def self.ask(call, principal, approval_id)
    Chat::ToolCall.run!(
      principal: principal, action_key: call.tool.action_key, workspace: call.resource.workspace, scope: call.scope, params: call.arguments,
      context: { source: AbilityGateway::SOURCE_WEB, approval_id: approval_id }.compact
    ) do |authorization|
      answer = call.tool.integration.executor.call(tool: call.tool, environment_row: call.environment_row, arguments: call.arguments,
                                                   box_key: principal.code_box_key)
      presented = call.present_result(answer)
      authorization.answer_failed!(text_of(presented)) if presented["isError"] == true
      presented
    end
  rescue Integrations::Error => error
    { "content" => [ { "type" => "text", "text" => "#{call.tool.action_key} failed: #{error.message}" } ], "isError" => true }
  end

  def self.text_of(result) = Array(dig(result, "content")).filter_map { |part| dig(part, "text") }.join("\n")

  def self.charts_of(result)
    Array(dig(dig(result, Integrations::Telemetry::STRUCTURED), Integrations::Telemetry::CHARTS)).each_with_index.map do |chart, index|
      Chart.new(id: "chart-#{index}", tool_call_id: "", title: dig(chart, "title").to_s, unit: dig(chart, "unit").to_s, step_position: nil,
                source_url: dig(chart, "link"), range_start: Time.zone.parse(dig(chart, "from").to_s), range_end: Time.zone.parse(dig(chart, "to").to_s),
                series: Array(dig(chart, "series")))
    end
  end

  def self.dig(hash, key) = hash.is_a?(Hash) ? hash[key] || hash[key.to_sym] : nil
  private_class_method :dig, :charts_of
end
