require "test_helper"
require Rails.root.join("db/migrate/20261005200000_move_chat_attachment_bytes_to_active_storage")

class MoveChatAttachmentBytesToActiveStorageTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    restore_blob_column
  end

  teardown do
    Chat::Attachment.reset_column_information
  end

  test "each file's encrypted bytes are attached to its own row and the column goes" do
    first = file_under_old_shape("first.log", "boom at 10:02")
    second = file_under_old_shape("second.log", "fine at 10:03")
    unread = file_under_old_shape("dump.zip", nil)

    migrate

    assert_not Chat::Attachment.column_names.include?("blob_id")
    assert_equal "boom at 10:02", Chat::Attachment.find(first).bytes
    assert_equal "fine at 10:03", Chat::Attachment.find(second).bytes
    assert_not Chat::Attachment.find(unread).sealed.attached?
  end

  test "running it again, or on an empty table, changes nothing" do
    migrate
    migrate

    file_under_new_shape = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "a.log", bytes: "a")
    assert_equal "a", Chat::Attachment.find(file_under_new_shape.id).bytes
  end

  test "it stops before dropping the column when a row would lose its bytes" do
    file_under_old_shape("first.log", "boom")
    Chat::Attachment.connection.execute("CREATE FUNCTION skip_sealed() RETURNS trigger AS $$ BEGIN IF NEW.name = 'sealed' THEN RETURN NULL; END IF; RETURN NEW; END $$ LANGUAGE plpgsql")
    Chat::Attachment.connection.execute("CREATE TRIGGER skip_sealed BEFORE INSERT ON active_storage_attachments FOR EACH ROW EXECUTE FUNCTION skip_sealed()")

    assert_raises(MoveChatAttachmentBytesToActiveStorage::Unmoved) { migrate }
    assert Chat::Attachment.connection.column_exists?(:chat_attachments, :blob_id)
  end

  private

  def migrate
    ActiveRecord::Migration.suppress_messages { MoveChatAttachmentBytesToActiveStorage.new.migrate(:up) }
    Chat::Attachment.reset_column_information
  end

  # The shape main had before, rolled back with the test's transaction.
  def restore_blob_column
    Chat::Attachment.connection.add_reference :chat_attachments, :blob, foreign_key: { to_table: :active_storage_blobs }, index: true
    Chat::Attachment.reset_column_information
  end

  # How a file was written then: the encrypted bytes uploaded as a bare blob, named on the row.
  def file_under_old_shape(name, bytes)
    blob = bytes && ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(ActiveRecord::Encryption.encryptor.encrypt(bytes)), filename: "chat-attachment",
      content_type: "application/octet-stream", identify: false
    )
    file = Chat::Attachment.create!(
      workspace: @workspace, uploaded_by: @member, filename: name, content_type: "text/plain", byte_size: bytes.to_s.bytesize,
      kind: bytes ? Chat::Attachment::KIND_TEXT : Chat::Attachment::KIND_UNREAD, refusal: (bytes ? nil : "not read")
    )
    file.update_columns(blob_id: blob.id) if blob
    file.id
  end
end
