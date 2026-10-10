# A workspace where Northflank runs a service called web, an alert started a run on an incident, and the run answered
# with a fix that restarts web, as the unattended rules and paging tests need.
module OnCallTestHelper
  def alert_run_with_restart_fix
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    @metrics = northflank.tools.create!(name: "query_metrics", description: "Metrics", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @api = northflank.tools.create!(name: "api_request", description: "Call the API", read_only: false, enabled: true, params_schema: { "type" => "object" })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE,
                                         external_id: "web-id", name: "web", integration_environment: @row,
                                         first_seen_at: Time.current, last_seen_at: Time.current)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_ALERT, max_turns: 10,
                                                       max_spend_cents: 400, thread_id: "1.1")
    @investigation.steps.create!(position: 1, tool_name: "query_metrics", label: "Metrics", action_key: @metrics.action_key,
                                 status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    @investigation.record_hypothesis!(assertion: "web is stuck", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    @finding = @investigation.conclude!(
      summary: "web stopped answering after a bad pool state", hypothesis_assertion: "web is stuck",
      evidence: [ { claim: "5xx rose at 03:02", steps: [ 1 ] } ],
      fix: { "summary" => "Restart web", "steps" => [
        { "kind" => "action", "description" => "Restart web", "tool" => "restart", "arguments" => { "resource" => "web" }, "undo" => "Nothing to undo, a restart keeps the version" }
      ] }
    )
    @plan = @finding.remediation_plan
  end

  def grant_investigator(tool)
    Ability::Grant.grant!(workspace: @workspace, principal: SystemAgent.investigator, target: { action: tool.ability_action })
  end

  def restart_rule(**attributes)
    @workspace.unattended_rules.create!({ resource: @web, capability: Integrations::Capabilities::RESTART, metric: "http_5xx", threshold: 50,
                                          minutes: 10, created_by: workspace_memberships(:alice_workspace_one) }.merge(attributes))
  end

  # What Northflank's metrics tool answers: one series per container, each a list of points.
  def metrics_answer(*series)
    now = Time.current
    charts = [ Integrations::Telemetry::Chart.new(
      title: "5xx responses", unit: "count", from: now - 10.minutes, to: now,
      series: series.each_with_index.map { |values, index| Integrations::Telemetry::Series.new(label: "web-#{index}", points: values.map { |value| [ now, value ] }) }
    ) ]
    Integrations::Telemetry.result(Integrations::Telemetry.charts_text(charts), link: nil, charts: charts)
  end
end
