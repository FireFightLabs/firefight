require "test_helper"

class PullRequestReview::AgentTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @review = PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)
    @chat = Chat.open!(owner: @review, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"))
    @agent = PullRequestReview::Agent.new(@review, chat: @chat)
  end

  test "a review reads as Halon, only reads, and reads every part in the review's own sandbox" do
    assert_equal SystemAgent.investigator, @agent.acting_principal
    assert @agent.reads_only?
    assert_not @agent.confirms?(nil)
    assert_equal "pr-review-#{@review.id}", @agent.code_box_key
  end

  test "every call goes through the gateway under the review's own source, named for the pull request" do
    Chat::ToolCall.expects(:run!).with do |**given|
      given[:principal] == SystemAgent.investigator && given[:context] == { source: AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, triggered_by_label: "Review of PR #7 in acme/api" }
    end.returns("read")

    assert_equal "read", @agent.tool_call(action_key: "github.list_files").value
    assert_equal "Pull request review", Ability::Source.label(AbilityGateway::SOURCE_PULL_REQUEST_REVIEW)
  end

  test "of Firefight's own tools only those that help review code are handed over, and every connection's are" do
    incident_tool = FirefightTools.all.find { |tool_class| Chat::Tools::Groups.of_firefight_tool(tool_class.name_value) == Chat::Tools::Groups::INCIDENT_HISTORY }
    other_tool = FirefightTools.all.find do |tool_class|
      group = Chat::Tools::Groups.of_firefight_tool(tool_class.name_value)
      group && PullRequestReview::Agent::FIREFIGHT_GROUPS.exclude?(group)
    end
    tools = [ incident_tool, other_tool ].map { |tool_class| stub(name: tool_class.name_value.to_s) } + [ stub(name: "github_run_shell") ]
    Chat::Tools.stubs(:presented).returns(Chat::Tools::Presented.new(loaded: tools, deferred: [], searched: false, held: false))

    loaded, = @agent.tools(FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"))

    names = loaded.map { |tool| tool.name.to_s }
    assert_includes names, incident_tool.name_value.to_s
    assert_includes names, "github_run_shell"
    assert_not_includes names, other_tool.name_value.to_s
    assert_includes names, Chat::Tools::ReadResult.new(@agent).name.to_s
  end
end
