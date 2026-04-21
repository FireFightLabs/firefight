# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_21_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "deleted_at"
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.jsonb "permissions", default: {}, null: false
    t.string "token_digest", null: false
    t.string "token_prefix", limit: 12, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["workspace_id", "deleted_at"], name: "index_api_keys_on_workspace_id_and_deleted_at"
    t.index ["workspace_id"], name: "index_api_keys_on_workspace_id"
  end

  create_table "catalog_attribute_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "attribute_type", null: false
    t.uuid "catalog_type_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.boolean "required", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_type_id", "key"], name: "index_catalog_attr_defs_on_type_and_key", unique: true
    t.index ["catalog_type_id"], name: "index_catalog_attribute_definitions_on_catalog_type_id"
  end

  create_table "catalog_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "attributes", default: {}, null: false
    t.uuid "catalog_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "external_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["catalog_type_id", "slug"], name: "index_catalog_entries_on_type_and_slug_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["catalog_type_id"], name: "index_catalog_entries_on_catalog_type_id"
    t.index ["workspace_id", "catalog_type_id"], name: "index_catalog_entries_on_workspace_id_and_catalog_type_id"
    t.index ["workspace_id", "source", "external_id"], name: "index_catalog_entries_external_identity", unique: true, where: "((source IS NOT NULL) AND (external_id IS NOT NULL))"
    t.index ["workspace_id"], name: "index_catalog_entries_on_workspace_id"
  end

  create_table "catalog_entry_relationships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "catalog_attribute_definition_id"
    t.datetime "created_at", null: false
    t.integer "position"
    t.string "relationship_key", null: false
    t.uuid "source_entry_id", null: false
    t.uuid "target_entry_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["catalog_attribute_definition_id"], name: "idx_on_catalog_attribute_definition_id_77676cd157"
    t.index ["source_entry_id", "catalog_attribute_definition_id"], name: "index_catalog_relationships_single_ref", unique: true, where: "(catalog_attribute_definition_id IS NOT NULL)"
    t.index ["source_entry_id", "target_entry_id", "relationship_key"], name: "index_catalog_relationships_uniqueness", unique: true
    t.index ["source_entry_id"], name: "index_catalog_entry_relationships_on_source_entry_id"
    t.index ["target_entry_id"], name: "index_catalog_entry_relationships_on_target_entry_id"
    t.index ["workspace_id"], name: "index_catalog_entry_relationships_on_workspace_id"
  end

  create_table "catalog_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "icon"
    t.string "kind", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.string "slug", null: false
    t.string "system_key"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "slug"], name: "index_catalog_types_on_workspace_and_slug_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["workspace_id", "system_key"], name: "index_catalog_types_on_workspace_id_and_system_key", unique: true, where: "(system_key IS NOT NULL)"
    t.index ["workspace_id"], name: "index_catalog_types_on_workspace_id"
  end

  create_table "environments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_environments_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_environments_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_environments_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_environments_on_workspace_id"
  end

  create_table "idempotency_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.uuid "resource_id", null: false
    t.string "resource_type", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_at"], name: "index_idempotency_keys_on_created_at"
    t.index ["workspace_id", "resource_type", "key"], name: "idx_on_workspace_id_resource_type_key_0235259f51", unique: true
    t.index ["workspace_id"], name: "index_idempotency_keys_on_workspace_id"
  end

  create_table "incident_action_updates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_type", null: false
    t.uuid "actor_id", null: false
    t.uuid "assignee_id"
    t.jsonb "changed_fields", default: [], null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "deleted_at"
    t.text "description", null: false
    t.uuid "incident_action_id", null: false
    t.uuid "incident_id", null: false
    t.string "message_ts"
    t.jsonb "platform_data", default: {}, null: false
    t.string "status", null: false
    t.string "update_type", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_incident_action_updates_on_actor_id"
    t.index ["assignee_id"], name: "index_incident_action_updates_on_assignee_id"
    t.index ["created_by_id"], name: "index_incident_action_updates_on_created_by_id"
    t.index ["incident_action_id", "created_at"], name: "idx_on_incident_action_id_created_at_ce446d496c"
    t.index ["incident_action_id"], name: "index_incident_action_updates_on_incident_action_id"
    t.index ["incident_id"], name: "index_incident_action_updates_on_incident_id"
    t.index ["update_type"], name: "index_incident_action_updates_on_update_type"
  end

  create_table "incident_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_type", default: "action", null: false
    t.uuid "assignee_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "deleted_at"
    t.text "description", null: false
    t.uuid "incident_id", null: false
    t.string "message_ts"
    t.jsonb "platform_data", default: {}
    t.string "status", default: "open"
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_incident_actions_on_assignee_id"
    t.index ["deleted_at"], name: "index_incident_actions_on_deleted_at"
    t.index ["incident_id", "action_type"], name: "index_incident_actions_on_incident_id_and_action_type"
    t.index ["incident_id", "status"], name: "index_incident_actions_on_incident_id_and_status"
  end

  create_table "incident_conditions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "condition_field", null: false
    t.uuid "conditionable_id", null: false
    t.string "conditionable_type", null: false
    t.datetime "created_at", null: false
    t.string "operator", null: false
    t.datetime "updated_at", null: false
    t.jsonb "values", default: [], null: false
    t.uuid "workspace_id", null: false
    t.index ["conditionable_type", "conditionable_id"], name: "index_incident_conditions_on_conditionable"
    t.index ["workspace_id"], name: "index_incident_conditions_on_workspace_id"
  end

  create_table "incident_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.uuid "eventable_id"
    t.string "eventable_type"
    t.uuid "incident_id", null: false
    t.jsonb "metadata", default: {}
    t.uuid "user_id"
    t.index ["event_type"], name: "index_incident_events_on_event_type"
    t.index ["eventable_type", "eventable_id"], name: "index_incident_events_on_eventable_type_and_eventable_id"
    t.index ["incident_id", "created_at"], name: "index_incident_events_on_incident_id_and_created_at"
    t.index ["incident_id"], name: "index_incident_events_on_incident_id"
    t.index ["metadata"], name: "index_incident_events_on_metadata", using: :gin
    t.index ["user_id"], name: "index_incident_events_on_user_id"
  end

  create_table "incident_field_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "field_type", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "option_source", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "key"], name: "index_incident_field_definitions_on_workspace_and_key_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["workspace_id"], name: "index_incident_field_definitions_on_workspace_id"
  end

  create_table "incident_form_fields", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "field_source_kind", null: false
    t.uuid "incident_field_definition_id"
    t.uuid "incident_form_id", null: false
    t.integer "position", null: false
    t.string "required_mode", default: "optional", null: false
    t.string "system_field_key"
    t.datetime "updated_at", null: false
    t.string "visibility_mode", default: "visible", null: false
    t.index ["incident_field_definition_id"], name: "index_incident_form_fields_on_incident_field_definition_id"
    t.index ["incident_form_id", "field_source_kind", "system_field_key"], name: "index_incident_form_fields_on_form_and_system_field", unique: true, where: "(system_field_key IS NOT NULL)"
    t.index ["incident_form_id", "incident_field_definition_id"], name: "index_incident_form_fields_on_form_and_field_definition", unique: true, where: "(incident_field_definition_id IS NOT NULL)"
    t.index ["incident_form_id"], name: "index_incident_form_fields_on_incident_form_id"
  end

  create_table "incident_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "lifecycle_event", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "slug"], name: "index_incident_forms_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_forms_on_workspace_id"
  end

  create_table "incident_lifecycle_stages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_incident_lifecycle_stages_on_key", unique: true
    t.index ["position"], name: "index_incident_lifecycle_stages_on_position"
  end

  create_table "incident_relationships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.uuid "incident_id", null: false
    t.uuid "related_incident_id", null: false
    t.string "relationship_type", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_incident_relationships_on_created_by_id"
    t.index ["incident_id", "related_incident_id", "relationship_type"], name: "idx_incident_relationships_unique_pair", unique: true
    t.index ["incident_id"], name: "index_incident_relationships_on_incident_id"
    t.index ["related_incident_id"], name: "index_incident_relationships_on_related_incident_id"
    t.index ["relationship_type"], name: "index_incident_relationships_on_relationship_type"
    t.check_constraint "incident_id <> related_incident_id", name: "chk_no_self_reference"
  end

  create_table "incident_role_assignments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "assigned_at", null: false
    t.uuid "assigned_by_id"
    t.datetime "created_at", null: false
    t.uuid "incident_id", null: false
    t.uuid "incident_role_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_membership_id", null: false
    t.index ["incident_id", "incident_role_id"], name: "idx_on_incident_id_incident_role_id_9839ecc130", unique: true
    t.index ["incident_id"], name: "index_incident_role_assignments_on_incident_id"
    t.index ["incident_role_id"], name: "index_incident_role_assignments_on_incident_role_id"
    t.index ["workspace_membership_id"], name: "index_incident_role_assignments_on_workspace_membership_id"
  end

  create_table "incident_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_incident_roles_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_incident_roles_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_incident_roles_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_roles_on_workspace_id"
  end

  create_table "incident_severities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "rank", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_incident_severities_on_deleted_at"
    t.index ["workspace_id", "is_default"], name: "index_incident_severities_on_workspace_id_and_is_default"
    t.index ["workspace_id", "position"], name: "index_incident_severities_on_workspace_id_and_position"
    t.index ["workspace_id", "rank"], name: "index_incident_severities_on_workspace_id_and_rank"
    t.index ["workspace_id", "slug"], name: "index_incident_severities_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_severities_on_workspace_id"
  end

  create_table "incident_statuses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.uuid "incident_lifecycle_stage_id", null: false
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_incident_statuses_on_deleted_at"
    t.index ["incident_lifecycle_stage_id"], name: "index_incident_statuses_on_incident_lifecycle_stage_id"
    t.index ["workspace_id", "is_default"], name: "index_incident_statuses_on_workspace_id_and_is_default"
    t.index ["workspace_id", "position"], name: "index_incident_statuses_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_incident_statuses_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_statuses_on_workspace_id"
  end

  create_table "incident_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.integer "position", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_incident_types_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_incident_types_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_incident_types_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_types_on_workspace_id"
  end

  create_table "incident_updates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "announcement_message_ts"
    t.jsonb "changed_fields", default: [], null: false
    t.datetime "channel_archived_at"
    t.string "channel_archived_by"
    t.string "channel_id"
    t.string "channel_name"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "custom_fields", default: {}, null: false
    t.datetime "declared_at", null: false
    t.uuid "declared_by_id"
    t.datetime "deleted_at"
    t.datetime "detected_at"
    t.string "identifier", null: false
    t.uuid "incident_id", null: false
    t.uuid "incident_severity_id", null: false
    t.uuid "incident_status_id", null: false
    t.uuid "incident_type_id"
    t.string "initial_message_ts"
    t.boolean "is_private", default: false, null: false
    t.uuid "lead_id"
    t.text "message"
    t.string "name"
    t.datetime "next_update_at"
    t.jsonb "platform_data", default: {}, null: false
    t.datetime "resolved_at"
    t.integer "sequence_number", null: false
    t.text "summary"
    t.string "update_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_incident_updates_on_created_by_id"
    t.index ["declared_by_id"], name: "index_incident_updates_on_declared_by_id"
    t.index ["incident_id", "created_at"], name: "index_incident_updates_on_incident_id_and_created_at"
    t.index ["incident_id"], name: "index_incident_updates_on_incident_id"
    t.index ["incident_severity_id"], name: "index_incident_updates_on_incident_severity_id"
    t.index ["incident_status_id"], name: "index_incident_updates_on_incident_status_id"
    t.index ["incident_type_id"], name: "index_incident_updates_on_incident_type_id"
    t.index ["lead_id"], name: "index_incident_updates_on_lead_id"
    t.index ["update_type"], name: "index_incident_updates_on_update_type"
  end

  create_table "incidents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "announcement_message_ts"
    t.datetime "channel_archived_at"
    t.string "channel_archived_by"
    t.string "channel_id"
    t.string "channel_name"
    t.datetime "created_at", null: false
    t.jsonb "custom_fields", default: {}
    t.datetime "declared_at", null: false
    t.uuid "declared_by_id"
    t.datetime "deleted_at"
    t.datetime "detected_at"
    t.string "identifier", null: false
    t.uuid "incident_severity_id", null: false
    t.uuid "incident_status_id", null: false
    t.uuid "incident_type_id"
    t.string "initial_message_ts"
    t.boolean "is_private", default: false
    t.string "name"
    t.datetime "next_update_at"
    t.jsonb "platform_data", default: {}
    t.datetime "resolved_at"
    t.integer "sequence_number", null: false
    t.string "source", null: false
    t.uuid "source_api_key_id"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["declared_at"], name: "index_incidents_on_declared_at"
    t.index ["declared_by_id"], name: "index_incidents_on_declared_by_id"
    t.index ["detected_at"], name: "index_incidents_on_detected_at"
    t.index ["incident_severity_id"], name: "index_incidents_on_incident_severity_id"
    t.index ["incident_status_id"], name: "index_incidents_on_incident_status_id"
    t.index ["incident_type_id"], name: "index_incidents_on_incident_type_id"
    t.index ["source"], name: "index_incidents_on_source"
    t.index ["workspace_id", "deleted_at"], name: "index_incidents_on_workspace_id_and_deleted_at"
    t.index ["workspace_id", "identifier"], name: "index_incidents_on_workspace_id_and_identifier", unique: true
    t.index ["workspace_id", "incident_status_id"], name: "index_incidents_on_workspace_id_and_incident_status_id"
    t.index ["workspace_id", "sequence_number"], name: "index_incidents_on_workspace_id_and_sequence_number", unique: true
    t.index ["workspace_id"], name: "index_incidents_on_workspace_id"
  end

  create_table "postmortem_updates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "changed_sections", default: [], null: false
    t.jsonb "content", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "edited_by_id", null: false
    t.uuid "incident_id", null: false
    t.string "model_id"
    t.uuid "postmortem_id", null: false
    t.string "status", null: false
    t.text "summary"
    t.string "title", null: false
    t.string "update_type", null: false
    t.datetime "updated_at", null: false
    t.index ["postmortem_id", "created_at"], name: "index_postmortem_updates_on_postmortem_id_and_created_at"
  end

  create_table "postmortems", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "content", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "generated_by_id", null: false
    t.uuid "incident_id", null: false
    t.string "message_ts"
    t.string "model_id"
    t.string "status", default: "draft", null: false
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_postmortems_on_incident_id", unique: true
  end

  create_table "product_areas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "lifecycle_state", default: "active", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.integer "tier"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_product_areas_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_product_areas_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_product_areas_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_product_areas_on_workspace_id"
  end

  create_table "service_dependencies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "dependency_id", null: false
    t.uuid "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dependency_id"], name: "index_service_dependencies_on_dependency_id"
    t.index ["service_id", "dependency_id"], name: "index_service_dependencies_on_service_id_and_dependency_id", unique: true
    t.index ["service_id"], name: "index_service_dependencies_on_service_id"
  end

  create_table "service_environments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "environment_id", null: false
    t.uuid "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id"], name: "index_service_environments_on_environment_id"
    t.index ["service_id", "environment_id"], name: "index_service_environments_on_service_id_and_environment_id", unique: true
    t.index ["service_id"], name: "index_service_environments_on_service_id"
  end

  create_table "service_product_areas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "product_area_id", null: false
    t.uuid "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_area_id"], name: "index_service_product_areas_on_product_area_id"
    t.index ["service_id", "product_area_id"], name: "index_service_product_areas_on_service_id_and_product_area_id", unique: true
    t.index ["service_id"], name: "index_service_product_areas_on_service_id"
  end

  create_table "services", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "alerts_url"
    t.string "color"
    t.datetime "created_at", null: false
    t.string "dashboard_url"
    t.datetime "deleted_at"
    t.text "description"
    t.string "docs_url"
    t.string "framework"
    t.string "language"
    t.string "lifecycle_state", default: "active", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "repo_url"
    t.string "runbook_url"
    t.string "service_type"
    t.string "slug", null: false
    t.integer "tier"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_services_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_services_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_services_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_services_on_workspace_id"
  end

  create_table "shoutouts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "from_member_id", null: false
    t.uuid "incident_id", null: false
    t.text "message", null: false
    t.string "slack_message_ts"
    t.uuid "to_member_id"
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_shoutouts_on_incident_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "solid_workflow_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.uuid "step_id"
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.index ["created_at"], name: "index_solid_workflow_events_on_created_at"
    t.index ["event_type"], name: "index_solid_workflow_events_on_event_type"
    t.index ["step_id"], name: "index_solid_workflow_events_on_step_id"
    t.index ["workflow_id", "created_at"], name: "index_workflow_events_on_workflow_and_created_at"
    t.index ["workflow_id"], name: "index_solid_workflow_events_on_workflow_id"
  end

  create_table "solid_workflow_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.jsonb "checkpoint"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "depends_on", default: [], array: true
    t.jsonb "input", default: {}, null: false
    t.text "last_error"
    t.integer "max_attempts", default: 5
    t.string "name", null: false
    t.jsonb "output", default: {}, null: false
    t.integer "position"
    t.jsonb "retry_config"
    t.datetime "run_at"
    t.text "skip_reason"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.index ["run_at"], name: "index_solid_workflow_steps_on_run_at"
    t.index ["status", "updated_at"], name: "index_solid_workflow_steps_on_status_and_updated_at"
    t.index ["status"], name: "index_solid_workflow_steps_on_status"
    t.index ["workflow_id", "name"], name: "index_solid_workflow_steps_on_workflow_id_and_name"
    t.index ["workflow_id", "status"], name: "index_solid_workflow_steps_on_workflow_id_and_status"
    t.index ["workflow_id"], name: "index_solid_workflow_steps_on_workflow_id"
  end

  create_table "solid_workflow_workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "cancellation_reason"
    t.string "cancelled_by"
    t.datetime "completed_at"
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.jsonb "state_timestamps", default: {}, null: false
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.string "workflow_class", null: false
    t.jsonb "workflow_config", default: {}
    t.index ["created_at"], name: "index_solid_workflow_workflows_on_created_at"
    t.index ["state", "updated_at"], name: "index_solid_workflow_workflows_on_state_and_updated_at"
    t.index ["state"], name: "index_solid_workflow_workflows_on_state"
    t.index ["subject_type", "subject_id", "state"], name: "index_workflows_on_subject_and_state"
    t.index ["subject_type", "subject_id"], name: "index_workflows_on_subject"
    t.index ["workflow_class"], name: "index_solid_workflow_workflows_on_workflow_class"
  end

  create_table "team_product_areas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "product_area_id", null: false
    t.uuid "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_area_id"], name: "index_team_product_areas_on_product_area_id"
    t.index ["team_id", "product_area_id"], name: "index_team_product_areas_on_team_id_and_product_area_id", unique: true
    t.index ["team_id"], name: "index_team_product_areas_on_team_id"
  end

  create_table "team_services", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "service_id", null: false
    t.uuid "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_team_services_on_service_id"
    t.index ["team_id", "service_id"], name: "index_team_services_on_team_id_and_service_id", unique: true
    t.index ["team_id"], name: "index_team_services_on_team_id"
  end

  create_table "teams", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "lifecycle_state", default: "active", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "product_owner"
    t.string "slug", null: false
    t.string "tech_owner"
    t.integer "tier"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_teams_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_teams_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_teams_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_teams_on_workspace_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "webhook_delinquency_trackers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "consecutive_failures_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "first_failure_at"
    t.datetime "updated_at", null: false
    t.uuid "webhook_id", null: false
    t.index ["webhook_id"], name: "index_webhook_delinquency_trackers_on_webhook_id", unique: true
  end

  create_table "webhook_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.text "error_message"
    t.string "event_type", null: false
    t.uuid "incident_event_id", null: false
    t.jsonb "request_body", default: {}
    t.jsonb "request_headers", default: {}
    t.integer "response_code"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "webhook_id", null: false
    t.index ["created_at"], name: "index_webhook_deliveries_on_created_at"
    t.index ["incident_event_id"], name: "index_webhook_deliveries_on_incident_event_id"
    t.index ["webhook_id", "created_at"], name: "index_webhook_deliveries_on_webhook_id_and_created_at"
    t.index ["webhook_id"], name: "index_webhook_deliveries_on_webhook_id"
  end

  create_table "webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "signing_secret", null: false
    t.jsonb "subscribed_events", default: [], null: false
    t.datetime "updated_at", null: false
    t.text "url", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "active"], name: "index_webhooks_on_workspace_id_and_active"
    t.index ["workspace_id"], name: "index_webhooks_on_workspace_id"
  end

  create_table "workspace_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.datetime "joined_at", null: false
    t.jsonb "platform_data", default: {}, null: false
    t.string "platform_user_id", null: false
    t.text "refresh_token"
    t.string "role", default: "member", null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["role"], name: "index_workspace_memberships_on_role"
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.index ["workspace_id", "platform_user_id"], name: "index_workspace_memberships_on_workspace_and_platform_user", unique: true
    t.index ["workspace_id"], name: "index_workspace_memberships_on_workspace_id"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "access_token"
    t.integer "archive_channel_delay_minutes", default: 60, null: false
    t.boolean "archive_channel_enabled", default: true, null: false
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "incidents_channel_id"
    t.datetime "installed_at", null: false
    t.string "name", null: false
    t.string "platform", default: "slack", null: false
    t.jsonb "platform_data", default: {}, null: false
    t.string "platform_id", null: false
    t.text "refresh_token"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["incidents_channel_id"], name: "index_workspaces_on_incidents_channel_id"
    t.index ["platform", "platform_id"], name: "index_workspaces_on_platform_and_platform_id", unique: true
    t.index ["platform"], name: "index_workspaces_on_platform"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_keys", "workspace_memberships", column: "created_by_id"
  add_foreign_key "api_keys", "workspaces"
  add_foreign_key "catalog_attribute_definitions", "catalog_types"
  add_foreign_key "catalog_entries", "catalog_types"
  add_foreign_key "catalog_entries", "workspaces"
  add_foreign_key "catalog_entry_relationships", "catalog_attribute_definitions"
  add_foreign_key "catalog_entry_relationships", "catalog_entries", column: "source_entry_id"
  add_foreign_key "catalog_entry_relationships", "catalog_entries", column: "target_entry_id"
  add_foreign_key "catalog_entry_relationships", "workspaces"
  add_foreign_key "catalog_types", "workspaces"
  add_foreign_key "environments", "workspaces"
  add_foreign_key "idempotency_keys", "workspaces"
  add_foreign_key "incident_action_updates", "incident_actions"
  add_foreign_key "incident_action_updates", "incidents"
  add_foreign_key "incident_action_updates", "workspace_memberships", column: "actor_id"
  add_foreign_key "incident_action_updates", "workspace_memberships", column: "assignee_id"
  add_foreign_key "incident_action_updates", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_actions", "incidents"
  add_foreign_key "incident_actions", "workspace_memberships", column: "assignee_id"
  add_foreign_key "incident_actions", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_conditions", "workspaces"
  add_foreign_key "incident_events", "incidents"
  add_foreign_key "incident_events", "workspace_memberships", column: "user_id"
  add_foreign_key "incident_field_definitions", "workspaces"
  add_foreign_key "incident_form_fields", "incident_field_definitions"
  add_foreign_key "incident_form_fields", "incident_forms"
  add_foreign_key "incident_forms", "workspaces"
  add_foreign_key "incident_relationships", "incidents"
  add_foreign_key "incident_relationships", "incidents", column: "related_incident_id"
  add_foreign_key "incident_relationships", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_role_assignments", "incident_roles"
  add_foreign_key "incident_role_assignments", "incidents"
  add_foreign_key "incident_role_assignments", "workspace_memberships"
  add_foreign_key "incident_role_assignments", "workspace_memberships", column: "assigned_by_id"
  add_foreign_key "incident_roles", "workspaces"
  add_foreign_key "incident_severities", "workspaces"
  add_foreign_key "incident_statuses", "incident_lifecycle_stages"
  add_foreign_key "incident_statuses", "workspaces"
  add_foreign_key "incident_types", "workspaces"
  add_foreign_key "incident_updates", "incident_severities"
  add_foreign_key "incident_updates", "incident_statuses"
  add_foreign_key "incident_updates", "incident_types"
  add_foreign_key "incident_updates", "incidents"
  add_foreign_key "incident_updates", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_updates", "workspace_memberships", column: "declared_by_id"
  add_foreign_key "incident_updates", "workspace_memberships", column: "lead_id"
  add_foreign_key "incident_updates", "workspaces"
  add_foreign_key "incidents", "api_keys", column: "source_api_key_id"
  add_foreign_key "incidents", "incident_severities"
  add_foreign_key "incidents", "incident_statuses"
  add_foreign_key "incidents", "incident_types"
  add_foreign_key "incidents", "workspace_memberships", column: "declared_by_id"
  add_foreign_key "incidents", "workspaces"
  add_foreign_key "postmortem_updates", "incidents"
  add_foreign_key "postmortem_updates", "postmortems"
  add_foreign_key "postmortem_updates", "workspace_memberships", column: "edited_by_id"
  add_foreign_key "postmortems", "incidents"
  add_foreign_key "postmortems", "workspace_memberships", column: "generated_by_id"
  add_foreign_key "product_areas", "workspaces"
  add_foreign_key "service_dependencies", "services"
  add_foreign_key "service_dependencies", "services", column: "dependency_id"
  add_foreign_key "service_environments", "environments"
  add_foreign_key "service_environments", "services"
  add_foreign_key "service_product_areas", "product_areas"
  add_foreign_key "service_product_areas", "services"
  add_foreign_key "services", "workspaces"
  add_foreign_key "shoutouts", "incidents"
  add_foreign_key "shoutouts", "workspace_memberships", column: "from_member_id"
  add_foreign_key "shoutouts", "workspace_memberships", column: "to_member_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_workflow_events", "solid_workflow_steps", column: "step_id"
  add_foreign_key "solid_workflow_events", "solid_workflow_workflows", column: "workflow_id"
  add_foreign_key "solid_workflow_steps", "solid_workflow_workflows", column: "workflow_id"
  add_foreign_key "team_product_areas", "product_areas"
  add_foreign_key "team_product_areas", "teams"
  add_foreign_key "team_services", "services"
  add_foreign_key "team_services", "teams"
  add_foreign_key "teams", "workspaces"
  add_foreign_key "webhook_delinquency_trackers", "webhooks"
  add_foreign_key "webhook_deliveries", "incident_events"
  add_foreign_key "webhook_deliveries", "webhooks"
  add_foreign_key "webhooks", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
end
