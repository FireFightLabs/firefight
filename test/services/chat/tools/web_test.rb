require "test_helper"

class Chat::Tools::WebTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                       max_turns: 10, max_spend_cents: 400)
  end

  test "a run searches the web with no grant, as a step it can cite, and the ledger holds the call" do
    WebLookup.expects(:search).with("sidekiq 7 retry", domains: nil).returns("[1] Retries\nhttps://github.com/sidekiq/sidekiq/wiki/Error-Handling\nThey retry 25 times.")
    search = Chat::Tools::Web.all(@investigation).find { |tool| tool.name == Chat::Tools::Web::SEARCH }

    answer = search.call(query: "sidekiq 7 retry")

    assert_includes answer, "https://github.com/sidekiq/sidekiq/wiki/Error-Handling"
    step = @investigation.steps.find_by!(action_key: Ability::Action::WEB_READ)
    assert_equal [ Investigation::Step::STATUS_SUCCEEDED, "Search the web for sidekiq 7 retry" ], [ step.status, step.label ]
    assert_equal [ Ability::Invocation::DECISION_ALLOW, SystemAgent.investigator ], [ step.invocation.decision, step.invocation.principal ]
  end

  test "a lookup one provider failed and the next answered is one step and one ledger row" do
    Integrations::WebSearch::Tavily.any_instance.stubs(:configured?).returns(true)
    Integrations::WebSearch::Firecrawl.any_instance.stubs(:configured?).returns(true)
    Integrations::WebSearch::Tavily.any_instance.expects(:search).raises(Integrations::WebSearch::Error, "Tavily answered 500: down")
    Integrations::WebSearch::Firecrawl.any_instance.expects(:search).returns([ Integrations::WebSearch::Result.new(title: "Retries", url: "https://sidekiq.org", text: "25 times") ])
    search = Chat::Tools::Web.all(@investigation).find { |tool| tool.name == Chat::Tools::Web::SEARCH }

    assert_includes search.call(query: "sidekiq retry"), "25 times"
    assert_equal 1, @investigation.steps.where(action_key: Ability::Action::WEB_READ).count
    assert_equal 1, Ability::Invocation.where(workspace: @workspace, action_key: Ability::Action::WEB_READ).count
  end

  test "a page that is not public, or a deployment with no search key, is said rather than read" do
    read = Chat::Tools::Web.all(@investigation).find { |tool| tool.name == Chat::Tools::Web::READ }

    assert_match "public http", read.call(url: "http://localhost/admin")
    Integrations::WebSearch::Tavily.any_instance.stubs(:configured?).returns(false)
    Integrations::WebSearch::Firecrawl.any_instance.stubs(:configured?).returns(false)
    assert_match "TAVILY_API_KEY or FIRECRAWL_API_KEY", read.call(url: "https://example.com/docs")
  end

  test "a workspace that switched web search off is offered neither tool, and its day's lookups are capped" do
    @workspace.update!(web_search_enabled: false)
    assert_empty Chat::Tools::Web.all(@investigation)

    @workspace.update!(web_search_enabled: true)
    Ability::Invocation.stubs(:where).returns(stub(where: stub(count: Workspace::Settings::WEB_LOOKUPS_PER_DAY)))
    WebLookup.expects(:search).never
    search = Chat::Tools::Web.all(@investigation).first
    Chat::Tools.expects(:mark_failed).with(@investigation, "call_1")
    assert_match "used its #{Workspace::Settings::WEB_LOOKUPS_PER_DAY} web lookups", search.call(query: "x", tool_call: stub(id: "call_1"))
  end

  test "an approval rule never holds a web lookup, and nobody is offered it as a grant" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    WebLookup.stubs(:search).returns("[1] x\nhttps://x.dev\ny")

    assert_includes Chat::Tools::Web.all(@investigation).first.call(query: "x"), "https://x.dev"
    assert_not_includes Ability::Grant.grantable_actions(@workspace).map(&:key), Ability::Action::WEB_READ
  end
end
