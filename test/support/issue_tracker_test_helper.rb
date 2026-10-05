# Connections to Linear and Jira with the tools keeping an item and its issue in step switched on, and their servers'
# answers, so a test never reaches a tracker.
module IssueTrackerTestHelper
  LINEAR_TOOLS = %w[save_issue get_issue list_issue_statuses list_users].freeze
  JIRA_TOOLS = %w[createjiraissue editjiraissue transitionjiraissue listjiraissuetransitions lookupjiraaccountid getjiraissue].freeze
  READS = %w[get_issue list_issue_statuses list_users listjiraissuetransitions lookupjiraaccountid getjiraissue].freeze

  def connect_tracker!(workspace, provider:, slug: provider, name: provider.capitalize, tools: nil)
    tools ||= provider == "linear" ? LINEAR_TOOLS : JIRA_TOOLS
    integration = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: name, slug: slug,
                                                 settings: { "server_url" => "https://mcp.example.com/#{provider}" })
    integration.integration_environments.create!
    tools.each do |tool|
      integration.tools.create!(name: tool, description: tool, read_only: READS.include?(tool), enabled: true, params_schema: { "type" => "object" })
    end
    integration
  end

  # Turns sync on for the workspace with the tracker, issues opened as creation says.
  def sync_with!(workspace, integration, creation: Workspace::IssueSync::ISSUE_CREATION_ASKED, target: { "team" => "ENG" }, secret: "whsec")
    workspace.update!(issue_tracker: integration.slug, issue_creation: creation, issue_tracker_target: target, issue_webhook_secret: secret)
  end

  def json_answer(data) = { "content" => [ { "type" => "text", "text" => data.to_json } ] }

  def text_answer(text) = { "content" => [ { "type" => "text", "text" => text } ] }

  def error_answer(text) = { "isError" => true, "content" => [ { "type" => "text", "text" => text } ] }

  # Each tool answers what answers names for it, and every call is kept in tracker_calls as its tool's name and arguments.
  def tracker_answers(answers)
    @tracker_calls = []
    answers.each do |name, answer|
      Integrations::McpExecutor.stubs(:call).with do |tool:, arguments:, **|
        tool.name == name && @tracker_calls << [ name, arguments ]
      end.returns(answer)
    end
  end

  def tracker_calls = @tracker_calls || []

  def linear_delivery(payload, secret: "whsec")
    body = payload.merge("webhookTimestamp" => (Time.current.to_f * 1000).to_i).to_json
    [ body, { "Linear-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body), "Content-Type" => "application/json" } ]
  end

  def jira_delivery(payload, secret: "whsec")
    body = payload.to_json
    [ body, { "X-Hub-Signature" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}", "Content-Type" => "application/json" } ]
  end
end
