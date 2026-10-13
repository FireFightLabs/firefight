require "test_helper"

# With specialists on, Halon's own tool list stays fixed and every read of a connected system goes to the specialist for
# its kind, which reads only what the asker may, never changes anything, and answers with the lines and links that
# show what it found and any change it would make, which Halon loads and the person confirms as any change.
class Chat::SpecialistsTest < ActiveSupport::TestCase
  ANSWERED = FirefightAi::AgentLoop::STATUS_ANSWERED
  INSIGHTS_LINK = "https://app.planetscale.com/larkspur/orders/main/insights".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @chat = @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @member)

    @planetscale = connect!("planetscale", "PlanetScale", "get_insights" => true, "execute_read_query" => true, "create_branch" => false)
    connect!("linear", "Linear", "list_issues" => true)
    connect!("custom_mcp", "Team tools", "team_read" => true)
    @turn.asks_specialists = true
  end

  test "a connection's kind comes from its provider's category in the registry, a provider's own wins, and Custom stays Halon's" do
    assert_equal Chat::Specialists::DATABASES, IntegrationProvider.specialist_for("planetscale")
    assert_equal Chat::Specialists::TICKETS, IntegrationProvider.specialist_for("linear")
    assert_equal Chat::Specialists::DEPLOYS, IntegrationProvider.specialist_for("northflank")
    assert_equal Chat::Specialists::CLOUD, IntegrationProvider.specialist_for("aws"), "a cloud's own kind wins over Cloud and hosting's"
    assert_nil IntegrationProvider.specialist_for("custom_mcp")

    named = IntegrationProvider.all.filter_map { |provider| IntegrationProvider.specialist_for(provider.key) }.uniq
    assert_equal Chat::Specialists::KEYS.sort, named.sort, "every kind the registry names is one a specialist reads, and each has a provider"
  end

  test "a specialist holds only its kind's reads that the asker may use, and never a change, which it may only propose" do
    live = Chat::Specialists::Live.new(@turn)
    agent = specialist_agent(Chat::Specialists::DATABASES)
    databases = Chat::Specialists.domain(Chat::Specialists::DATABASES)

    held = live.tools(agent, databases).map { |tool| tool.name.to_s }
    assert_includes held, "planetscale_get_insights"
    assert_includes held, "planetscale_execute_read_query"
    assert_includes held, Chat::Tools::ReadResult.tool_name
    assert_not_includes held, "planetscale_create_branch", "a change is never in a specialist's hands"
    assert_not_includes held, "linear_list_issues", "another kind's reads are another specialist's"
    assert_not_includes held, "custom_mcp_team_read"
    assert_equal [ "planetscale_create_branch" ], live.changes(agent, databases).map(&:name)

    nobody = Chat::Specialists::Live.new(Conversation::Turn.new(@conversation, asker: nil))
    assert_not_includes nobody.tools(agent_for(nil, Chat::Specialists::DATABASES), databases).map { |tool| tool.name.to_s }, "planetscale_get_insights"
    assert_equal Chat::Tools::STATE_NOT_GRANTED, nobody.views.find { |view| view.domain.key == Chat::Specialists::DATABASES }.state
    assert_equal Chat::Tools::STATE_NOT_CONNECTED, live.views.find { |view| view.domain.key == Chat::Specialists::CODE }.state
  end

  # A chat decides each turn. In auto it asks specialists only where the provider does not search tools and the tools the
  # asker may use do not fit the held tools budget, and on or off overrides that.
  test "in auto a turn asks specialists only when its tools do not fit and the provider does not search, and on or off override it" do
    choice = FirefightAi::ModelChoice.new(model: "gpt-4o")
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(10)
    assert Chat::Specialists.ask?(@turn, choice), "past the budget"

    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000_000)
    assert_not Chat::Specialists.ask?(@turn, choice), "every tool fits, so today's way"

    FirefightAi.configuration.stubs(:held_tools_budget).returns(10)
    FirefightAi.stubs(:tool_search?).returns(true)
    assert_not Chat::Specialists.ask?(@turn, choice), "a provider that searches tools keeps the long tail out already"

    FirefightAi.configuration.stubs(:specialists).returns(:on)
    assert Chat::Specialists.ask?(@turn, choice)
    FirefightAi.configuration.stubs(:specialists).returns(:off)
    FirefightAi.stubs(:tool_search?).returns(false)
    assert_not Chat::Specialists.ask?(@turn, choice)
  end

  # An admin holds more of Firefight's own tools than fit the budget on their own, so counting them would switch every
  # admin's chat to specialists. Only the connection reads that would go to specialists are counted.
  test "in auto an admin in a small workspace stays on today's way, since only the connections' reads are counted" do
    FirefightAi.stubs(:tool_search?).returns(false)
    choice = FirefightAi::ModelChoice.new(model: "gpt-4o")
    admin = workspace_memberships(:alice_workspace_one)
    assert admin.admin_access?, "the fixture is an admin"

    everything = Chat::Tools.catalog(Conversation::Turn.new(@conversation, asker: admin)).select(&:tool).map(&:tool)
    assert_not FirefightAi.fits_up_front?(everything), "an admin's own tools alone are past the budget"
    assert_not Chat::Specialists.ask?(Conversation::Turn.new(@conversation, asker: admin), choice)
  end

  # Cloudflare's execute runs scripts, and its read guard shows a call made as method and path only reads. A specialist
  # holds such a tool in that reading shape, and a general tool no guard can read stays with Halon.
  test "a specialist reads through a general tool whose guard shows a call reads, and never holds one no guard covers" do
    connect!("cloudflare", "Cloudflare", "execute" => false)
    live = Chat::Specialists::Live.new(@turn)

    cloud = live.tools(agent_for(@member, Chat::Specialists::CLOUD), Chat::Specialists.domain(Chat::Specialists::CLOUD))
    execute = cloud.find { |tool| tool.name.to_s == "cloudflare_execute" }
    assert execute, "the cloud specialist holds Cloudflare's execute"
    assert_includes execute.parameters_schema.deep_stringify_keys["properties"].keys, "path", "in its reading shape"
    assert_includes live.changes(agent_for(@member, Chat::Specialists::CLOUD), Chat::Specialists.domain(Chat::Specialists::CLOUD)).map(&:name), "cloudflare_execute"

    databases = live.tools(agent_for(@member, Chat::Specialists::DATABASES), Chat::Specialists.domain(Chat::Specialists::DATABASES)).map { |tool| tool.name.to_s }
    assert_not_includes databases, "planetscale_create_branch", "a general tool with no guard stays Halon's"
  end

  test "Halon holds its own tools from the start, never a connection's read, and finds a change by searching" do
    FirefightAi.stubs(:tool_search?).returns(true)

    presented = Chat::Tools.presented(@turn, FirefightAi::ModelChoice.new(model: "gpt-4o"))
    loaded = presented.loaded.map { |tool| tool.name.to_s }
    deferred = presented.deferred.map { |tool| tool.name.to_s }

    assert presented.specialists
    assert_includes loaded, Mcp::Tools::SEARCH_INCIDENTS
    assert_not_includes loaded + deferred, "planetscale_get_insights"
    assert_not_includes loaded + deferred, "linear_list_issues"
    assert_includes deferred, "planetscale_create_branch"
    assert_includes deferred, "custom_mcp_team_read", "a connection no specialist reads stays Halon's own"
  end

  test "where Halon holds its tools, it holds no connection's read or change, and open_tools loads a change by name but never a read" do
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000_000)
    offered = []
    presented = Chat::Tools.presented(@turn, FirefightAi::ModelChoice.new(model: "gpt-4o"))
    held = presented.loaded.map { |tool| tool.name.to_s }

    assert presented.held
    assert_includes held, Mcp::Tools::RESOLVE_INCIDENT
    assert_includes held, "custom_mcp_team_read"
    assert_not_includes held, "planetscale_get_insights"
    assert_not_includes held, "planetscale_create_branch"

    open = Chat::Tools::Open.new(@turn, offer: ->(tools) { offered.concat(tools.map(&:name)) }, presented: presented)
    assert_includes open.description, Chat::Tools::Open::SPECIALISTS
    said = open.call(group: "databases", tools: [ "planetscale_get_insights", "planetscale_create_branch" ])

    assert_equal [ "planetscale_create_branch" ], offered
    assert_includes said, "read by the databases specialist, so ask it with ask_specialist"
  end

  # Past the budget a chat that asks specialists still holds what a tool search would hand it whole, so its tool list
  # does not change as it reads.
  test "past the budget Halon still holds Firefight's reads and the capabilities that read, and loads the rest by name" do
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(12_000)
    held = Chat::Tools.presented(@turn, FirefightAi::ModelChoice.new(model: "gpt-4o")).loaded.map { |tool| tool.name.to_s }

    assert_includes held, Mcp::Tools::SEARCH_INCIDENTS
    assert_not_includes held, Mcp::Tools::RESOLVE_INCIDENT
    assert_not_includes held, "custom_mcp_team_read"
    assert_not_includes held, "planetscale_get_insights"
  end

  test "a turn that does not ask specialists is handed exactly what it is today, on today's prompt" do
    FirefightAi.stubs(:tool_search?).returns(true)
    on_version = FirefightAi::Responder.new(@workspace, inferable: nil, specialists: true).prompt_version
    @turn.asks_specialists = false

    presented = Chat::Tools.presented(@turn, FirefightAi::ModelChoice.new(model: "gpt-4o"))
    tools = Conversation::Tools.for(@turn, offer: ->(_tools) { }, helpers: share(nil), presented: presented).map { |tool| tool.name.to_s }

    assert_not presented.specialists
    assert_includes presented.deferred.map { |tool| tool.name.to_s }, "planetscale_get_insights"
    assert_not_includes tools, Chat::Tools::AskSpecialist::NAME
    assert_includes tools, Chat::Tools::Helpers::NAME
    off_version = FirefightAi::Responder.new(@workspace, inferable: nil).prompt_version
    assert_not_equal on_version, off_version, "the bench tells the two ways apart by the prompt's version"
    assert_not_includes FirefightAi::Responder.new(@workspace, inferable: nil).send(:template_text), FirefightAi::Manual::SPECIALIST_READS
  end

  test "a specialist reports what it found with the lines and links that show it, and a change it proposes is never loaded for Halon" do
    tool = Chat::Tools::AskSpecialist.new(@turn, share: share(Chat::Specialists::Live.new(@turn)))
    Chat::Tools.expects(:offer_to).never
    handed = nil
    FirefightAi::Specialist.any_instance.stubs(:run).with do |chat:, tools:, playbook:, answered:, **|
      handed = tools.map { |each| each.name.to_s }
      read!(chat, "s_1", "planetscale_get_insights", "open connections 498 of 500 since 13:39\n#{INSIGHTS_LINK}")
      report = tools.find { |each| each.name == Chat::Specialists::Report::NAME }
      said = report.call(summary: "worker holds the connections", findings: [
        { "claim" => "The database is at its connection limit", "lines" => [ "open connections 498 of 500 since 13:39" ], "links" => [ INSIGHTS_LINK ] }
      ], proposed_changes: [ { "tool" => "planetscale_create_branch", "arguments" => { "name" => "fix" }, "because" => [ "planetscale_get_insights: 498 of 500" ] } ])
      assert_equal "Reported.", said
      assert answered.call
      assert_includes playbook, "Your kind of system: Databases"
      true
    end.returns(FirefightAi::AgentLoop::Outcome.new(status: ANSWERED, turns_used: 2, spent_micros: 0))

    said = tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_ask", name: Chat::Tools::AskSpecialist::NAME, arguments: {}),
                     "asks" => [ { "domain" => "databases", "objective" => "Who holds the connections?" } ])

    assert_not_includes handed, "planetscale_create_branch"
    assert_includes said, "Specialists reported, 1 of 1:"
    assert_includes said, "Shows: open connections 498 of 500 since 13:39"
    assert_includes said, "Link: #{INSIGHTS_LINK}"
    assert_includes said, "Proposed change: planetscale_create_branch {\"name\":\"fix\"}"
    assert_includes said, "planetscale_create_branch: #{Chat::Specialists::CONFIRM_FIRST}"
    helper = @chat.helpers.sole
    assert_equal [ Chat::Specialists::DATABASES, Chat::Helper::STATUS_REPORTED ], [ helper.domain, helper.status ]
    assert_equal "planetscale_create_branch", helper.proposed_changes.sole["tool"]
  end

  test "a report is refused for a line or a link the specialist never read, or a change that is not its kind's" do
    own = specialist_agent(Chat::Specialists::DATABASES).chat
    read!(own, "s_1", "planetscale_get_insights", "open connections 498 of 500")
    report = Chat::Specialists::Report.new(own, changes: [ Chat::Specialists::Change.new(name: "planetscale_create_branch", line: "Creates a branch") ])

    said = report.call(summary: "x", findings: [ { "claim" => "Full", "lines" => [ "1000 open connections" ], "links" => [ "https://made.up/page" ] } ],
                       proposed_changes: [ { "tool" => "linear_create_issue", "arguments" => {}, "because" => [ "search_logs: errors" ] } ])

    assert_not report.taken?
    assert_includes said, "This line is not in anything you read, so copy it exactly: 1000 open connections"
    assert_includes said, "This link is not in anything you read: https://made.up/page"
    assert_includes said, "linear_create_issue is not a change of your kind"
    assert_includes said, "Name the reads behind linear_create_issue by the tools you called."
  end

  # Seen in a chat, a code specialist read a deploy's diff and found it changed only a test, then sent its findings one
  # per call at the top level. The empty report was taken and Halon read "nothing reported", so the innocent deploy kept
  # the blame. A report that says nothing is refused, a finding given at the top level is taken, and a later call adds.
  test "a report that says nothing is refused, and findings sent one call each are all kept" do
    own = specialist_agent(Chat::Specialists::CODE).chat
    read!(own, "s_1", "github_show_commit", "test/system/agent_chat_paging_test.rb | 2 +-\n1 file changed, 1 insertion(+), 1 deletion(-)")
    read!(own, "s_2", "github_fetch_file", "found = scope.limit(size + 1).to_a")
    report = Chat::Specialists::Report.new(own, changes: [])

    assert_equal Chat::Specialists::Report::EMPTY, report.call
    assert_not report.taken?

    said = report.call(claim: "The commit changes only a test.", lines: [ "1 file changed, 1 insertion(+), 1 deletion(-)" ])
    assert_equal "Reported.", said
    assert_equal "Reported.", report.call(claim: "The paging code is untouched.", lines: [ "found = scope.limit(size + 1).to_a" ])

    assert report.taken?
    assert_includes report.text, "1. The commit changes only a test."
    assert_includes report.text, "Shows: 1 file changed, 1 insertion(+), 1 deletion(-)"
    assert_includes report.text, "2. The paging code is untouched."

    finding = { "claim" => "The commit changes only a test.", "lines" => [ "1 file changed, 1 insertion(+), 1 deletion(-)" ] }
    assert_equal "Reported.", report.call(findings: [ finding ] * (Chat::Specialists::Report::MAX_FINDINGS - 2))
    said = report.call(claim: "One more.", lines: [ "found = scope.limit(size + 1).to_a" ])
    assert_includes said, "Not reported. The report holds #{Chat::Specialists::Report::MAX_FINDINGS} findings already"
    assert_not_includes report.text, "One more.", "a finding that does not fit is refused, never dropped after Reported."
  end

  # Seen on the big workspace bench, a rollback went ahead on thin reads. A specialist's report is another model's words,
  # so neither it nor what the specialist read backs a change, and Halon confirms the finding with a read of its own.
  test "a change backed only by a specialist goes back to Halon, and one naming Halon's own read is put to the person as any change" do
    asked!("orders is out of connections, fix it")
    read!(@chat, "call_ask", Chat::Tools::AskSpecialist::NAME, "Specialists reported, 1 of 1:\n1. worker holds the connections")
    helper = Chat::Helper.start!(chat: @chat, tool_call_id: "call_ask", since: 1.minute.ago,
                                 checks: [ Chat::Helpers::Check.new(title: "Databases", brief: "Read", deep: false, domain: Chat::Specialists::DATABASES) ]).sole
    own = Chat.open!(owner: helper, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o-mini"))
    read!(own, "s_1", "planetscale_get_insights", "498 of 500")
    because = { "because" => [ "planetscale_get_insights: 498 of 500 connections" ] }

    assert_match Chat::Tools::LookFirst::BOUNCE, Chat::Tools::LookFirst.refusal(@turn, because), "what the specialist read is not Halon's read"
    assert_match Chat::Tools::LookFirst::BOUNCE, Chat::Tools::LookFirst.refusal(@turn, { "because" => [ "ask_specialist: worker holds the connections" ] }),
                 "a specialist's report never backs a change"

    read!(@chat, "call_own", "planetscale_get_insights", "498 of 500")
    assert_nil Chat::Tools::LookFirst.refusal(@turn, because), "Halon's own read confirming the finding backs it"

    change = Chat::Tools.catalog(@turn).find { |entry| entry.name == "planetscale_create_branch" }.tool
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_change", name: "planetscale_create_branch", arguments: because)
    call = RubyLLM::ToolCall.new(id: "call_change", name: "planetscale_create_branch", arguments: because)
    assert change.requires_approval?, "the loaded change asks the person as any change does"
    assert_nil change.approval_resolver.call(call), "it waits for the person's answer"
    @chat.request_decisions!([ "call_change" ])
    support = Chat::Tools.confirmation(@chat.tool_calls.find_by!(tool_call_id: "call_change")).support_points
    assert_equal [ "498 of 500 connections" ], support.map(&:text)
  end

  private

  def connect!(provider, name, tools)
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: name, slug: provider,
                                                  settings: { "server_url" => "https://mcp.example.com/#{provider}" })
    integration.integration_environments.create!
    tools.each do |tool, reads|
      created = integration.tools.create!(name: tool, description: "#{tool.humanize}.", params_schema: { "type" => "object" }, enabled: true, read_only: reads)
      Ability::Grant.create!(workspace: @workspace, principal: @member, action: created.reload.ability_action) unless reads
    end
    integration
  end

  def specialist_agent(domain) = agent_for(@member, domain)

  def agent_for(asker, domain)
    helper = Chat::Helper.start!(chat: @chat, tool_call_id: "call_#{SecureRandom.hex(3)}", since: 1.minute.ago,
                                 checks: [ Chat::Helpers::Check.new(title: domain, brief: "Read", deep: false, domain: domain) ]).sole
    Chat.open!(owner: helper, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o-mini"))
    Chat::Helpers::Agent.new(helper.reload, parent: Conversation::Turn.new(@conversation, asker: asker, reads_only: true))
  end

  def share(specialists)
    Chat::Helpers::Share.new(
      purse: FirefightAi::AgentLoop::Purse.new, max_spend_cents: 400, since: 1.minute.ago, canceled: -> { false }, moved: ->(_key) { },
      fresh_parent: -> { Conversation::Turn.new(@conversation, asker: @member, reads_only: true) },
      choose: ->(_deep) { FirefightAi::ModelChoice.new(model: "gpt-4o-mini") }, inferable: @conversation, member: @member, specialists: specialists
    )
  end

  def asked!(words) = @chat.messages.create!(role: Chat::Message::ROLE_USER, content: words)

  def read!(chat, tool_call_id, name, answer)
    message = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: {})
    call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer))
  end
end
