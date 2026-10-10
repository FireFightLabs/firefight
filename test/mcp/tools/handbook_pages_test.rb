require "test_helper"

class Mcp::Tools::HandbookPagesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @releases = handbook_page!(@workspace, "How we release", "Tag main.", by: @admin)
  end

  test "pages are listed in order and one is read whole by its title or id" do
    handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: incident_roles(:communications_lead_ws1))

    listed = call(Mcp::Tools::ListHandbookPages, @member).structured_content[:pages]
    assert_equal [ "How we release", Chat::HandbookPage::DIRECTING_TITLE ], listed.pluck(:title)
    assert_equal "communications_lead", listed.last[:incident_role]

    read = call(Mcp::Tools::GetHandbookPage, @member, page: "how we release").structured_content
    assert_equal [ @releases.id, "Tag main.", @releases.current_wording.id ], read.values_at(:id, :text, :wording_id)
    assert call(Mcp::Tools::GetHandbookPage, @member, page: "Nothing").error?
  end

  test "an admin sets freeze windows on a page, and reading the page shows them" do
    window = { "name" => "Friday afternoons", "repeat" => "weekly", "time_zone" => "UTC", "start_day" => 5, "start_time" => "15:00", "end_day" => 1,
               "end_time" => "08:00" }
    call(Mcp::Tools::UpsertHandbookPage, @admin, page: "How we release", freeze_windows: [ window ])

    assert_equal [ window ], call(Mcp::Tools::GetHandbookPage, @member, page: "How we release").structured_content[:freeze_windows]
    assert Workspace::FreezeWindows.rules(@workspace).one?
  end

  test "an admin adds a page and changes one, each in the activity log, and an edit over someone else's is refused" do
    added = call(Mcp::Tools::UpsertHandbookPage, @admin, title: "Who owns what", text: "Payments owns checkout.")
    assert_equal "Who owns what", added.structured_content[:title]
    assert_equal 1, Ability::Invocation.where(workspace: @workspace, action_key: "handbook.create", source: AbilityGateway::SOURCE_MCP).count

    seen = @releases.current_wording.id
    changed = call(Mcp::Tools::UpsertHandbookPage, @admin, page: "How we release", text: "Run the deploy workflow.", wording_id: seen)
    assert_not changed.error?
    assert_equal "Run the deploy workflow.", @releases.reload.text

    stale = call(Mcp::Tools::UpsertHandbookPage, @admin, page: "How we release", text: "Over it", wording_id: seen)
    assert stale.error?
    assert_equal "Run the deploy workflow.", @releases.reload.text
  end

  test "deleting needs the permission, and a synced page is refused with why" do
    assert call(Mcp::Tools::DeleteHandbookPage, @member, page: "How we release").error?
    assert Chat::HandbookPage.exists?(@releases.id)

    source = Chat::HandbookSource.create!(workspace: @workspace, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/web", path: "docs/")
    synced = Chat::HandbookPage.create_written!(@workspace, title: "Deploys", text: "Run make deploy", by: nil, kind: Chat::HandbookPage::KIND_SYNCED,
                                                            source: source, source_path: "docs/deploys.md")
    refused = call(Mcp::Tools::DeleteHandbookPage, @admin, page: "Deploys")
    assert_match "Change it there, or stop syncing it.", refused.content.sole[:text]
    assert Chat::HandbookPage.exists?(synced.id)

    assert_not call(Mcp::Tools::DeleteHandbookPage, @admin, page: "How we release").error?
    assert_not Chat::HandbookPage.exists?(@releases.id)
  end

  private

  def call(tool, principal, **args)
    Mcp::ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)
  end
end
