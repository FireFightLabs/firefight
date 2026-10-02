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

  test "a page that is not public, or a deployment with no search key, is said rather than read" do
    read = Chat::Tools::Web.all(@investigation).find { |tool| tool.name == Chat::Tools::Web::READ }

    assert_match "public http", read.call(url: "http://localhost/admin")
    Integrations::Tavily.stubs(:configured?).returns(false)
    assert_match "TAVILY_API_KEY", read.call(url: "https://example.com/docs")
  end

  test "a workspace that switched web search off is offered neither tool, and its day's lookups are capped" do
    @workspace.update!(web_search_enabled: false)
    assert_empty Chat::Tools::Web.all(@investigation)

    @workspace.update!(web_search_enabled: true)
    Ability::Invocation.stubs(:where).returns(stub(where: stub(count: Workspace::Settings::WEB_LOOKUPS_PER_DAY)))
    WebLookup.expects(:search).never
    search = Chat::Tools::Web.all(@investigation).first
    assert_match "used its #{Workspace::Settings::WEB_LOOKUPS_PER_DAY} web lookups", search.call(query: "x")
  end

  test "an approval rule never holds a web lookup, and nobody is offered it as a grant" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    WebLookup.stubs(:search).returns("[1] x\nhttps://x.dev\ny")

    assert_includes Chat::Tools::Web.all(@investigation).first.call(query: "x"), "https://x.dev"
    assert_not_includes Ability::Grant.grantable_actions(@workspace).map(&:key), Ability::Action::WEB_READ
  end
end
