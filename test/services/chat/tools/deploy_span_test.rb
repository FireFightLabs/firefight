require "test_helper"

# Seen in a chat, Halon blamed the live deploy for slow pages from its title alone. The deploy carried 41 commits since
# the one before it, and the one its title named changed a test. Then it offered a rollback that would have undone all of
# them, migrations included, without knowing. A deploy read now says what the live deploy carried, read through the
# code host holding its repository, and a rollback says what it undoes before anyone is asked.
class Chat::Tools::DeploySpanTest < ActiveSupport::TestCase
  Deploys = Integrations::Capabilities::Deploys
  History = Integrations::Capabilities::History
  Comparison = Integrations::Capabilities::Comparison
  LIVE = "c04750f3a75ad16eee1e11f6451c8315954700a2".freeze
  BEFORE = "96e8c6a49c48aa11bb22cc33dd44ee55ff667788".freeze
  OLDER = "b80dd5da0a32aa11bb22cc33dd44ee55ff667788".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @northflank = connect!("northflank", "Northflank", "list_deployments" => true, "api_request" => false)
    @web = place!(@northflank, ResourceMap::KIND_SERVICE, "web", "web")
    @github = connect!("github", "GitHub", "compare_commits" => true)
    repository = place!(@github, ResourceMap::KIND_REPOSITORY, "acme/firefight", "acme/firefight")
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: repository, relation: ResourceMap::RELATION_BUILT_FROM,
                              origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
    deploys!
  end

  test "a deploy read says what the live deploy carried since the one before it, read through the code host" do
    compare!(BEFORE, LIVE, commits: 41, paths: [ *migrations(25), "app/models/chat.rb", "test/system/agent_chat_paging_test.rb" ])
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    revoke_investigator_packs!(@workspace)
    grant!(investigation.acting_principal, Integration::Tool.where(integration: [ @northflank, @github ]))

    answer = tool(investigation, "recent_deploys").call(resource: "web")

    assert_includes answer, "c04750f went out after 96e8c6a, so it carried every commit between them, not only the newest one its title names."
    assert_includes answer, "41 commits and 27 changed files (database migrations 25, application code 1, tests 1)."
    assert_match(/<tool_result tool="github_compare_commits" step="\d+" trust="untrusted">\n41 commits/, answer, "commit titles are anyone's words, framed with the step a run cites")
    assert_includes answer, "db/migrate/20261001000001_step_1.rb"
    assert_includes answer, "https://github.com/acme/firefight/compare/#{BEFORE}...#{LIVE}", "the comparison links to its page"
    assert_includes answer, "Rolling back to 96e8c6a would undo all of it, the database migrations included."
    assert_equal %w[github.compare_commits northflank.list_deployments], investigation.steps.pluck(:action_key).sort, "each read is its own step, in Activity"
  end

  test "with no code host holding the repository, the span is still said, with why what it changed was not read" do
    ResourceMap::Link.where(from_resource: @web).delete_all
    turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)

    answer = tool(turn, "recent_deploys").call(resource: "web")

    assert_includes answer, "c04750f went out after 96e8c6a, so it carried every commit between them"
    assert_includes answer, "What they changed was not read: No code host on the map holds the repository web is built from."
    assert_not Ability::Invocation.exists?(workspace: @workspace, action_key: "github.compare_commits")
  end

  test "a comparison the code host fails is said framed as its words, and the deploys still answer" do
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool.name == "compare_commits" }.raises(Integrations::Error, "404 Not Found")
    turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)

    answer = tool(turn, "recent_deploys").call(resource: "web")

    assert_includes answer, "Latest 3 deployments of web"
    assert_match(/What they changed was not read\.\n<tool_result tool="github_compare_commits" trust="untrusted">\n404 Not Found/, answer)
  end

  test "a watch following deploys reads them alone, without comparing on every check" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    agent = Conversation::Watches::Agent.new(workspace: @workspace, asker: @member, conversation: conversation)

    answer = agent.tools["recent_deploys"].tool.call(resource: "web")

    assert_includes answer, "Latest 3 deployments of web"
    assert_not_includes answer, "What the live deploy carried"
  end

  test "a rollback is first answered with what it undoes, migrations included, and is put to the person once Halon has seen it" do
    compare!(OLDER, LIVE, commits: 43, paths: [ *migrations(25), "app/models/chat.rb" ])
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    chat = conversation.chat_record
    turn = Conversation::Turn.new(conversation, asker: @member)
    chat.messages.create!(role: Chat::Message::ROLE_USER, content: "pages are slow, roll web back to b80dd5d")
    read!(chat, "call_deploys", "search_logs", "web pages take 4 seconds since 20:44")
    because = [ "search_logs: web pages take 4 seconds since 20:44" ]
    arguments = { "resource" => "web", "to" => "dep-older", "intent" => "Roll web back", "because" => because }
    rollback = tool(turn, "rollback")
    Integrations::NativeExecutor.expects(:call).with { |tool:, **| tool.name == "api_request" }.never

    first = change!(chat, "call_rollback_1", arguments)
    assert rollback.approval_resolver.call(first), "sent back before anyone is asked"
    answer = rollback.call(tool_call: first, **arguments.symbolize_keys)

    assert_includes answer, "Rolling back to b80dd5d would undo every commit since it, up to c04750f, which web runs now."
    assert_includes answer, "43 commits and 26 changed files"
    assert_includes answer, "The old version would run against the database these migrations left."
    assert_equal [ true, Chat::StepOutcome::FAILURE_REFUSED ], chat.tool_calls.where(tool_call_id: "call_rollback_1").pick(:failed, :failure_kind)
    chat.tool_calls.find_by!(tool_call_id: "call_rollback_1").update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer))

    second = change!(chat, "call_rollback_2", arguments)
    assert_nil rollback.approval_resolver.call(second), "once Halon has seen what it undoes, the person is asked as before"
  end

  test "a rollback to the deploy a read already showed the span of is put to the person at once" do
    compare!(BEFORE, LIVE, commits: 41, paths: [ "app/models/chat.rb" ])
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    chat = conversation.chat_record
    turn = Conversation::Turn.new(conversation, asker: @member)
    chat.messages.create!(role: Chat::Message::ROLE_USER, content: "what went out to web?")
    said = tool(turn, "recent_deploys").call(resource: "web")
    read!(chat, "call_deploys", "recent_deploys", said)
    arguments = { "resource" => "web", "to" => "dep-before", "intent" => "Roll web back", "because" => [ "recent_deploys: c04750f is live" ] }

    assert_nil tool(turn, "rollback").approval_resolver.call(change!(chat, "call_rollback", arguments))
  end

  private

  def deploys!
    listed = [
      Deploys::Deploy.new(id: "dep-live", commit: LIVE, status: History::SUCCEEDED, live: true, started_at: 2.hours.ago),
      Deploys::Deploy.new(id: "dep-before", commit: BEFORE, status: History::SUCCEEDED, live: false, started_at: 22.hours.ago),
      Deploys::Deploy.new(id: "dep-older", commit: OLDER, status: History::SUCCEEDED, live: false, started_at: 23.hours.ago)
    ]
    text = "Latest 3 deployments of web, newest first.\n#{LIVE.first(12)} \"Wait for every earlier question in the chat paging test (#803)\""
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool.name == "list_deployments" }
                                .returns(Deploys.with_deploys({ "content" => [ { "type" => "text", "text" => text } ] }, listed))
  end

  def compare!(base, head, commits:, paths:)
    answer = Comparison.with_comparison("#{commits} commits", commits: commits, titles: [ "Wait for every earlier question (#803)" ], paths: paths,
                                                              link: "https://github.com/acme/firefight/compare/#{base}...#{head}")
    Integrations::NativeExecutor.stubs(:call).with { |tool:, arguments:, **| tool.name == "compare_commits" && arguments == { "repo" => "acme/firefight", "base" => base, "head" => head } }
                                .returns(answer)
  end

  def migrations(count) = (1..count).map { |number| format("db/migrate/2026100100%04d_step_#{number}.rb", number) }

  def tool(agent_run, name) = Chat::Tools.catalog(agent_run).find { |entry| entry.name == name }.tool

  def connect!(provider, name, tools)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name, slug: provider)
    integration.integration_environments.create!(credentials: { token: "x" }.to_json)
    tools.each { |tool, reads| integration.tools.create!(name: tool, description: tool, read_only: reads, enabled: true, params_schema: { "type" => "object" }) }
    integration
  end

  def place!(integration, kind, name, external_id)
    ResourceMap::Resource.create!(workspace: @workspace, provider: integration.provider, account: "acme", kind: kind, external_id: external_id,
                                  name: name, integration_environment: integration.integration_environments.sole,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def grant!(principal, tools)
    tools.each { |tool| Ability::Grant.create!(workspace: @workspace, principal: principal, action: tool.reload.ability_action) }
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end

  def read!(chat, tool_call_id, name, answer)
    message = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: { "resource" => "web" })
    call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer))
  end

  def change!(chat, tool_call_id, arguments)
    message = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: "rollback", arguments: arguments)
    RubyLLM::ToolCall.new(id: tool_call_id, name: "rollback", arguments: arguments)
  end
end
