require "test_helper"

class Chat::Tools::SearchHandbookTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)
    FirefightAi.stubs(:embed).raises(FirefightAi::TerminalError.new("No embedding model", reason: "test"))
    @guide = handbook_page!(@workspace, "Release guide", "## Before\n\nFreeze merges an hour ahead.\n\n## Rollback\n\nRun the rollback workflow, then check checkout's error rate.")
    HandbookIndexJob.perform_now(@guide.id)
    other = handbook_page!(workspaces(:slack_workspace_two), "Theirs", "Their rollback runs by hand.")
    HandbookIndexJob.perform_now(other.id)
  end

  test "a page is split into sections, its words kept without where they sit, and its text encrypted" do
    chunks = @guide.chunks.to_a

    assert_equal [ "Release guide > Before", "Release guide > Rollback" ], chunks.map(&:heading_path)
    stored = Chat::HandbookChunk.connection.select_values("SELECT text FROM chat_handbook_chunks WHERE handbook_page_id = '#{@guide.id}'")
    assert(stored.none? { |text| text.include?("rollback") })
    document = Chat::HandbookChunk.connection.select_value("SELECT document::text FROM chat_handbook_chunks WHERE handbook_page_id = '#{@guide.id}' AND position = 1")
    assert_not_includes document, ":"
  end

  test "it finds the section that answers in this workspace's handbook, whole, with a link to its heading" do
    answer = Chat::Tools::SearchHandbook.new(@turn).call("query" => "rollback checkout")

    assert_includes answer, "Release guide > Rollback"
    assert_includes answer, "Run the rollback workflow, then check checkout's error rate."
    assert_includes answer, @guide.url(heading: "Rollback")
    assert_includes answer, "#rollback"
    assert_not_includes answer, "Their rollback"
  end

  test "a run searches as the investigator, which an admin can stop by revoking its grant" do
    @workspace.grant_agent_defaults!
    run = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    assert_includes Chat::Tools::SearchHandbook.new(run).call("query" => "freeze"), "Freeze merges an hour ahead."

    @workspace.ability_grants.where(principal: SystemAgent.investigator, action: Ability::Action.system!(Ability::Action::HANDBOOK_READ)).destroy_all
    assert_not_includes Chat::Tools::SearchHandbook.new(run).call("query" => "freeze"), "Freeze merges"
  end

  test "an empty query is refused and nothing matching says so" do
    assert_equal "Say what to look for in query.", Chat::Tools::SearchHandbook.new(@turn).call("query" => " ")
    assert_equal "Nothing in the handbook matched \"kubernetes\".", Chat::Tools::SearchHandbook.new(@turn).call("query" => "kubernetes")
  end
end
