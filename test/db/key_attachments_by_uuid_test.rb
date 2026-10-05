require "test_helper"
require Rails.root.join("db/migrate/20261005180000_key_attachments_by_uuid")

class KeyAttachmentsByUuidTest < ActiveSupport::TestCase
  setup do
    restore_bigint_owners
    @digits = archived_event(incidents(:active_critical_ws1), "572f0000-0000-4000-8000-000000000001", "digits.txt")
    @same_digits = file_event(incidents(:active_critical_ws1), "572a0000-0000-4000-8000-000000000002", "same-digits.txt")
    @letter = archived_event(incidents(:active_critical_ws1), "c0000000-0000-4000-8000-000000000003", "letter.txt")
    @other_workspace = archived_event(incidents(:active_p0_ws2), "d0000000-0000-4000-8000-000000000004", "other.txt")
    @unrecorded = file_event(incidents(:active_critical_ws1), "99000000-0000-4000-8000-000000000005", "unrecorded.txt")
    @unrecorded_blob = attach_mangled(@unrecorded, "unrecorded.txt")
    @stray_blob = attach_mangled(@same_digits, "stray.txt")
  end

  teardown do
    ActiveStorage::Attachment.reset_column_information
    ActiveStorage::VariantRecord.reset_column_information
  end

  test "each attachment goes back to the event that recorded its blob, and an unproven one is detached" do
    migrate

    assert_equal "digits.txt", IncidentEvent.find(@digits.id).archived_file.download
    assert_equal "letter.txt", IncidentEvent.find(@letter.id).archived_file.download
    assert_equal "other.txt", IncidentEvent.find(@other_workspace.id).archived_file.download
    assert_nil IncidentEvent.find(@same_digits.id).archived_file
    assert_nil IncidentEvent.find(@unrecorded.id).archived_file
    assert_equal [ @digits.id, @letter.id, @other_workspace.id ].sort, ActiveStorage::Attachment.where(record_type: IncidentEvent.name).pluck(:record_id).sort
    assert ActiveStorage::Blob.exists?(@unrecorded_blob.id), "a detached file is kept, only its owner is dropped"
    assert ActiveStorage::Blob.exists?(@stray_blob.id)
    assert_equal :uuid, ActiveStorage::VariantRecord.columns_hash["id"].type
  end

  test "running it again changes nothing" do
    migrate
    owners = ActiveStorage::Attachment.order(:id).pluck(:id, :record_id)

    migrate

    assert_equal owners, ActiveStorage::Attachment.order(:id).pluck(:id, :record_id)
  end

  private

  def migrate
    ActiveRecord::Migration.suppress_messages { KeyAttachmentsByUuid.new.migrate(:up) }
    ActiveStorage::Attachment.reset_column_information
    ActiveStorage::VariantRecord.reset_column_information
  end

  # The shape the tables had before the migration, rolled back with the test's transaction.
  def restore_bigint_owners
    connection = ActiveRecord::Base.connection
    connection.remove_index :active_storage_attachments, name: KeyAttachmentsByUuid::UNIQUENESS_INDEX
    connection.remove_column :active_storage_attachments, :record_id
    connection.add_column :active_storage_attachments, :record_id, :bigint, null: false
    connection.add_index :active_storage_attachments, [ :record_type, :record_id, :name, :blob_id ], name: KeyAttachmentsByUuid::UNIQUENESS_INDEX, unique: true
    connection.drop_table :active_storage_variant_records
    connection.create_table :active_storage_variant_records do |table|
      table.bigint :blob_id, null: false
      table.string :variation_digest, null: false
    end
    ActiveStorage::Attachment.reset_column_information
  end

  def file_event(incident, id, name)
    incident.incident_events.create!(id: id, event_type: IncidentEvent::MESSAGE_FILE_SHARED, metadata: { "file_name" => name })
  end

  def archived_event(incident, id, name)
    event = file_event(incident, id, name)
    blob = attach_mangled(event, name)
    event.update!(metadata: event.metadata.merge("blob_id" => blob.id, "object_key" => blob.key))
    event
  end

  # What the bigint column kept of a uuid, its leading digits or zero.
  def attach_mangled(event, name)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(name), filename: name, content_type: "text/plain")
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      VALUES ('artifact', 'IncidentEvent', #{event.id[/\A\d+/].to_i}, #{blob.id}, now())
    SQL
    blob
  end
end
