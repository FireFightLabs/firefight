require "test_helper"

class Chat::InstructionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @auth = catalog_entries(:auth_service)
    @team = catalog_entries(:platform_team)
  end

  test "a chat or run follows its owning team's instructions, then the thing's own, most specific last, and the handbook apart" do
    own = write("Check the session store first", scope: @auth)
    team = write("Page the platform team before any rollback", scope: @team)
    write("Unrelated service rules", scope: catalog_entries(:production_env))
    handbook = handbook_page!(@workspace, "General", "Never restart the primary database").current_wording

    assert_equal [ team, own ], Chat::Instruction.for_subjects(@workspace, [ @auth ], principal: @member)
    assert_equal "Platform Team (team): Page the platform team before any rollback", team.line
    assert_equal "General", handbook.label
  end

  test "a place holds one set of instructions, and an edit keeps the old wording as history" do
    original = write("Check logs first", scope: @auth)
    duplicate = Chat::Instruction.new(workspace: @workspace, scope: @auth, text: "Something else")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.full_messages.sole, "already has instructions. Edit them instead."

    revised = original.revise!(text: "Check metrics first", by: @member)

    assert_equal [ revised ], Chat::Instruction.for_subjects(@workspace, [ @auth ], principal: @member)
    assert_equal revised, original.reload.superseded_by
    assert original.superseded_at
  end

  test "an edit or removal of instructions someone already changed does nothing" do
    note = write("Check logs first", scope: @auth)
    stale = Chat::Instruction.find(note.id)
    note.revise!(text: "Check metrics first", by: @member)

    assert_nil stale.revise!(text: "Check traces first", by: @member)
    assert_not stale.retire!
    assert_equal [ "Check metrics first" ], Chat::Instruction.current.where(workspace: @workspace).map(&:text)
  end

  test "the text is stored encrypted" do
    note = write("Never restart the primary database")

    assert_not_includes Chat::Instruction.connection.select_value("SELECT text FROM chat_instructions WHERE id = '#{note.id}'"), "primary"
  end

  test "instructions that look like they hold a secret are refused, since they reach every prompt" do
    note = Chat::Instruction.new(workspace: @workspace, scope: @auth, text: "Connect with postgres://app:hunter2@db.internal/prod")

    assert_not note.valid?
    assert_match "looks like it holds a secret", note.errors.full_messages.sole
  end

  test "two first saves for one place at the same moment leave one, and the second hears why" do
    write("Check logs first", scope: @auth)
    racing = Chat::Instruction.new(workspace: @workspace, scope: @auth, text: "Check metrics first", added_by: @member)

    error = assert_raises(ActiveRecord::RecordInvalid) { racing.save!(validate: false) }
    assert_equal "Auth Service (service) already has instructions. Edit them instead.", error.record.errors.full_messages.sole
    assert_equal 1, Chat::Instruction.current.where(workspace: @workspace, scope: @auth).count
  end

  private

  def write(text, scope: nil)
    return handbook_page!(@workspace, "General", text, by: @member).current_wording unless scope

    Chat::Instruction.create!(workspace: @workspace, scope: scope, text: text, added_by: @member)
  end
end
