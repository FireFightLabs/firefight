require "test_helper"
require Rails.root.join("db/migrate/20261027130000_encrypt_memory_state_reasons")

class EncryptMemoryStateReasonsTest < ActiveSupport::TestCase
  setup do
    @memory = Chat::Memory.create!(workspace: workspaces(:slack_workspace_one), text: "Checkout retries twice", state: Chat::Memory::STATE_DISPUTED)
    Chat::Memory.where(id: @memory.id).update_all(Arel.sql("state_reason = 'The client sets three retries.'"))
  end

  test "a reason saved in plain text is read as it was, encrypted by the migration, and put back by its reverse" do
    assert_equal "The client sets three retries.", @memory.reload.state_reason

    migrate(:up)
    assert ActiveRecord::Encryption.encryptor.encrypted?(stored)
    assert_equal "The client sets three retries.", @memory.reload.state_reason

    migrate(:up)
    assert_equal "The client sets three retries.", @memory.reload.state_reason, "an encrypted reason is left as it is"

    migrate(:down)
    assert_equal "The client sets three retries.", stored
  end

  private

  # Read raw, since reading through the model would decrypt it.
  def stored = Chat::Memory.connection.select_value(Chat::Memory.sanitize_sql_array([ "SELECT state_reason FROM chat_memories WHERE id = ?", @memory.id ]))

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { EncryptMemoryStateReasons.new.migrate(direction) }
end
