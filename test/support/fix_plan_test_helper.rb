# A run on an incident that named a cause, with a fix whose first step runs a Cloudflare tool, whose second is for a
# person after it, and whose third is a code change.
module FixPlanTestHelper
  def build_fix_plan(workspace)
    investigation = workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      thread_id: "1.1", status: Investigation::STATUS_SUCCEEDED
    )
    investigation.steps.create!(position: 1, tool_name: "commit_lookup", label: "Commit lookup", action_key: "github.commit_lookup",
                                status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    cloudflare = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    cloudflare.integration_environments.create!
    cloudflare.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    investigation.record_hypothesis!(assertion: "A WAF rule blocks checkout", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    investigation.conclude!(
      summary: "A WAF rule blocked checkout", hypothesis_assertion: "A WAF rule blocks checkout",
      evidence: [ { claim: "The rule was added at 14:02", steps: [ 1 ] } ],
      fix: { "summary" => "Remove the rule", "steps" => [
        { "kind" => "action", "description" => "Delete the rule", "tool" => "cloudflare_execute", "arguments" => { "code" => "delete" } },
        { "kind" => "manual", "description" => "Tell security", "depends_on" => [ 1 ] },
        { "kind" => "pull_request", "description" => "Drop the rule from dns.tf", "repository" => "acme/infra" }
      ] }
    ).remediation_plan
  end
end
