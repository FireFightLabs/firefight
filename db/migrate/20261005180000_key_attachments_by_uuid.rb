# Every model here has a uuid key, but Active Storage kept its owners in a bigint column, which stored
# only the leading digits of each id. A row survives only when the archived file event it names
# recorded archiving that exact blob, and every other row is detached. The blobs are kept.
class KeyAttachmentsByUuid < ActiveRecord::Migration[8.1]
  UNIQUENESS_INDEX = "index_active_storage_attachments_uniqueness".freeze
  VARIANTS_UNIQUENESS_INDEX = "index_active_storage_variant_records_uniqueness".freeze

  def up
    key_attachments_by_uuid unless uuid?(:active_storage_attachments, :record_id)
    key_variant_records_by_uuid unless uuid?(:active_storage_variant_records, :id)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def key_attachments_by_uuid
    total = select_value("SELECT COUNT(*) FROM active_storage_attachments")
    add_column :active_storage_attachments, :record_uuid, :uuid
    recovered = exec_update(<<~SQL.squish)
      UPDATE active_storage_attachments AS attachments
      SET record_uuid = events.id
      FROM active_storage_blobs AS blobs, incident_events AS events
      WHERE attachments.record_type = #{quote(IncidentEvent.name)}
        AND attachments.name = 'artifact'
        AND blobs.id = attachments.blob_id
        AND events.event_type = #{quote(IncidentEvent::MESSAGE_FILE_SHARED)}
        AND events.metadata ->> 'blob_id' = attachments.blob_id::text
        AND events.metadata ->> 'object_key' = blobs.key
        AND attachments.record_id = COALESCE(SUBSTRING(events.id::text FROM '^[0-9]+')::bigint, 0)
        AND (SELECT COUNT(*) FROM incident_events AS claims WHERE claims.metadata ->> 'blob_id' = attachments.blob_id::text) = 1
    SQL
    detached = exec_delete("DELETE FROM active_storage_attachments WHERE record_uuid IS NULL")

    remove_index :active_storage_attachments, name: UNIQUENESS_INDEX
    remove_column :active_storage_attachments, :record_id
    rename_column :active_storage_attachments, :record_uuid, :record_id
    change_column_null :active_storage_attachments, :record_id, false
    add_index :active_storage_attachments, [ :record_type, :record_id, :name, :blob_id ], name: UNIQUENESS_INDEX, unique: true

    say "active_storage_attachments: #{total} rows, #{recovered} matched to their owner, #{detached} detached"
  end

  # Variant records own attachments too, so their key has to match the column. They are a cache
  # Active Storage rebuilds on demand, and their attachments were detached above.
  def key_variant_records_by_uuid
    cleared = select_value("SELECT COUNT(*) FROM active_storage_variant_records")
    drop_table :active_storage_variant_records
    create_table :active_storage_variant_records, id: :uuid do |t|
      t.belongs_to :blob, null: false, index: false
      t.string :variation_digest, null: false
      t.index [ :blob_id, :variation_digest ], name: VARIANTS_UNIQUENESS_INDEX, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    say "active_storage_variant_records: #{cleared} cached rows cleared"
  end

  def uuid?(table, column) = columns(table).find { |candidate| candidate.name == column.to_s }.type == :uuid
end
