require "test_helper"
require Rails.root.join("db/migrate/20261006090100_move_seed_pack_memories_to_encrypted_notes")

class MoveSeedPackMemoriesToEncryptedNotesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "Auth Service keeps sessions in Redis", state: Chat::Memory::STATE_UNCONFIRMED)
    @line = @memory.line
    @run = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400,
      seed_pack: { "incident" => { "identifier" => "INC-001" }, "memories" => [ @line ], "instructions" => [ "Whole workspace: Check logs first" ] }
    )
    @plain = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4,
                                               max_spend_cents: 400, seed_pack: { "incident" => { "identifier" => "INC-002" } }, status: Investigation::STATUS_SUCCEEDED)
  end

  test "memories and instructions leave the plain pack for the encrypted notes, the run reads the same text, and they move back" do
    migrate(:up)

    @run.reload
    assert_equal({ "incident" => { "identifier" => "INC-001" } }, @run.seed_pack)
    assert_equal [ @line ], @run.starting_facts["memories"]
    assert_equal [ "Whole workspace: Check logs first" ], @run.starting_facts["instructions"]
    assert_equal @memory.id, @run.seed_notes["memories"].sole["id"]
    assert_not_includes Investigation.where(id: @run.id).pick(Arel.sql("seed_notes")), "Redis"
    assert_nil @plain.reload.seed_notes

    migrate(:down)
    @run.reload
    assert_equal [ @line ], @run.seed_pack["memories"]
    assert_nil @run.seed_notes
  end

  private

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { MoveSeedPackMemoriesToEncryptedNotes.new.migrate(direction) }
end
