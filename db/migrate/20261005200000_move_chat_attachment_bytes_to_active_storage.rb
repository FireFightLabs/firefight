# A chat attachment kept its encrypted bytes as a bare blob named by blob_id, since Active Storage could not key an
# owner by uuid then. Each blob is attached to its row as sealed, every row is checked to have it, and only then
# does the column go. The blobs and their bytes are untouched.
class MoveChatAttachmentBytesToActiveStorage < ActiveRecord::Migration[8.1]
  NAME = "sealed".freeze
  RECORD_TYPE = "Chat::Attachment".freeze

  class Unmoved < StandardError; end

  def up
    return unless column_exists?(:chat_attachments, :blob_id)

    attached = exec_update(<<~SQL.squish)
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      SELECT #{quote(NAME)}, #{quote(RECORD_TYPE)}, files.id, files.blob_id, files.created_at
      FROM chat_attachments AS files
      WHERE files.blob_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM active_storage_attachments AS kept
          WHERE kept.record_type = #{quote(RECORD_TYPE)} AND kept.record_id = files.id AND kept.name = #{quote(NAME)}
        )
    SQL

    unmoved = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM chat_attachments AS files
      WHERE files.blob_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM active_storage_attachments AS kept
          WHERE kept.record_type = #{quote(RECORD_TYPE)} AND kept.record_id = files.id AND kept.name = #{quote(NAME)}
            AND kept.blob_id = files.blob_id
        )
    SQL
    raise Unmoved, "#{unmoved} chat attachments would lose their bytes, so blob_id is kept" if unmoved.positive?

    remove_reference :chat_attachments, :blob, foreign_key: { to_table: :active_storage_blobs }, index: true
    say "chat_attachments: #{attached} files attached as #{NAME}"
  end

  def down
    return if column_exists?(:chat_attachments, :blob_id)

    add_reference :chat_attachments, :blob, foreign_key: { to_table: :active_storage_blobs }, index: true
    execute(<<~SQL.squish)
      UPDATE chat_attachments AS files SET blob_id = kept.blob_id
      FROM active_storage_attachments AS kept
      WHERE kept.record_type = #{quote(RECORD_TYPE)} AND kept.record_id = files.id AND kept.name = #{quote(NAME)}
    SQL
    execute("DELETE FROM active_storage_attachments WHERE record_type = #{quote(RECORD_TYPE)} AND name = #{quote(NAME)}")
  end
end
