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

ActiveRecord::Schema[8.1].define(version: 2026_07_28_103000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "ability_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id"
    t.string "kind", null: false
    t.string "key", null: false
    t.string "risk_level", null: false
    t.boolean "reversible", default: true, null: false
    t.jsonb "params_schema", default: {}, null: false
    t.string "source_type"
    t.uuid "source_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_ability_actions_on_system_key", unique: true, where: "(workspace_id IS NULL)"
    t.index ["source_type", "source_id"], name: "index_ability_actions_on_source_type_and_source_id"
    t.index ["workspace_id", "key"], name: "index_ability_actions_on_workspace_key", unique: true, where: "(workspace_id IS NOT NULL)"
  end

  create_table "ability_approvals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "principal_type", null: false
    t.uuid "principal_id", null: false
    t.string "principal_label", null: false
    t.string "action_key", null: false
    t.string "request_digest", null: false
    t.jsonb "scope", default: {}, null: false
    t.jsonb "params", default: {}, null: false
    t.string "required_role", null: false
    t.string "status", default: "pending", null: false
    t.uuid "approver_id"
    t.datetime "resolved_at"
    t.datetime "consumed_at"
    t.uuid "incident_id"
    t.string "slack_channel_id"
    t.string "slack_message_ts"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "self_approvable", default: true, null: false
    t.index ["principal_type", "principal_id"], name: "index_ability_approvals_on_principal_type_and_principal_id"
    t.index ["workspace_id", "status", "created_at"], name: "idx_on_workspace_id_status_created_at_15ac906fa7"
  end

  create_table "ability_grants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "principal_type", null: false
    t.uuid "principal_id", null: false
    t.uuid "role_id"
    t.uuid "action_id"
    t.jsonb "scope", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_ability_grants_on_action_id"
    t.index ["principal_type", "principal_id", "action_id"], name: "index_ability_grants_on_principal_action", unique: true, where: "(action_id IS NOT NULL)"
    t.index ["principal_type", "principal_id", "role_id"], name: "index_ability_grants_on_principal_role", unique: true, where: "(role_id IS NOT NULL)"
    t.index ["role_id"], name: "index_ability_grants_on_role_id"
    t.check_constraint "role_id IS NOT NULL AND action_id IS NULL OR role_id IS NULL AND action_id IS NOT NULL", name: "ability_grants_exactly_one_target"
  end

  create_table "ability_invocations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "principal_type", null: false
    t.uuid "principal_id", null: false
    t.string "principal_label", null: false
    t.string "triggered_by_label"
    t.string "action_key", null: false
    t.string "risk_level"
    t.jsonb "scope", default: {}, null: false
    t.jsonb "params", default: {}, null: false
    t.string "decision", null: false
    t.string "idempotency_key", null: false
    t.uuid "incident_id"
    t.string "outcome"
    t.string "error_summary"
    t.integer "duration_ms"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "approval_id"
    t.index ["action_key"], name: "index_ability_invocations_on_action_key"
    t.index ["principal_type", "principal_id", "created_at"], name: "index_ability_invocations_on_principal"
    t.index ["workspace_id", "created_at"], name: "index_ability_invocations_on_workspace_id_and_created_at"
  end

  create_table "ability_role_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "role_id", null: false
    t.uuid "action_id", null: false
    t.jsonb "default_scope", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id", "action_id"], name: "index_ability_role_actions_on_role_id_and_action_id", unique: true
  end

  create_table "ability_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "slug"], name: "index_ability_roles_on_workspace_id_and_slug", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "description"
    t.boolean "enabled", default: true, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "slug"], name: "index_agents_on_workspace_id_and_slug", unique: true
  end

  create_table "alert_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "incident_id", null: false
    t.string "content_signature", null: false
    t.datetime "window_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_alert_groups_on_incident_id"
    t.index ["workspace_id", "content_signature", "window_expires_at"], name: "index_alert_groups_on_signature_window"
    t.index ["workspace_id"], name: "index_alert_groups_on_workspace_id"
  end

  create_table "alert_sources", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "endpoint_path", null: false
    t.string "secret_token", null: false
    t.jsonb "config", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_received_at"
    t.datetime "last_rejected_at"
    t.string "last_rejection_reason"
    t.index ["endpoint_path"], name: "index_alert_sources_on_endpoint_path", unique: true
    t.index ["workspace_id", "name"], name: "index_alert_sources_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_alert_sources_on_workspace_id"
  end

  create_table "alerts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "alert_source_id", null: false
    t.string "external_id", null: false
    t.string "fingerprint", null: false
    t.string "status", default: "firing", null: false
    t.jsonb "fields", default: {}, null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "event_count", default: 1, null: false
    t.string "routing_state", default: "pending", null: false
    t.datetime "received_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "resolved_at"
    t.datetime "routed_at"
    t.uuid "incident_id"
    t.uuid "alert_group_id"
    t.string "channel_id"
    t.string "channel_message_id"
    t.datetime "last_notified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "matched_policy_rule_id"
    t.integer "routing_attempts", default: 0, null: false
    t.index ["alert_group_id"], name: "index_alerts_on_alert_group_id"
    t.index ["alert_source_id", "external_id"], name: "index_alerts_on_alert_source_id_and_external_id", unique: true
    t.index ["alert_source_id", "fingerprint", "status"], name: "index_alerts_on_alert_source_id_and_fingerprint_and_status"
    t.index ["alert_source_id", "fingerprint"], name: "index_alerts_on_open_fingerprint", unique: true, where: "((status)::text = 'firing'::text)"
    t.index ["alert_source_id"], name: "index_alerts_on_alert_source_id"
    t.index ["incident_id"], name: "index_alerts_on_incident_id"
    t.index ["matched_policy_rule_id"], name: "index_alerts_on_matched_policy_rule_id"
    t.index ["received_at"], name: "index_alerts_on_pending_received_at", where: "((routing_state)::text = 'pending'::text)"
    t.index ["workspace_id", "last_seen_at"], name: "index_alerts_on_workspace_id_and_last_seen_at"
    t.index ["workspace_id", "routing_state"], name: "index_alerts_on_workspace_id_and_routing_state"
    t.index ["workspace_id"], name: "index_alerts_on_workspace_id"
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "created_by_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", limit: 12, null: false
    t.jsonb "permissions", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_membership_id"
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["workspace_id", "deleted_at"], name: "index_api_keys_on_workspace_id_and_deleted_at"
    t.index ["workspace_id"], name: "index_api_keys_on_workspace_id"
    t.index ["workspace_membership_id"], name: "index_api_keys_on_workspace_membership_id"
  end

  create_table "catalog_attribute_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "catalog_type_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "attribute_type", null: false
    t.boolean "required", default: false, null: false
    t.integer "position", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_type_id", "key"], name: "index_catalog_attr_defs_on_type_and_key", unique: true
    t.index ["catalog_type_id"], name: "index_catalog_attribute_definitions_on_catalog_type_id"
  end

  create_table "catalog_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "catalog_type_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.jsonb "attributes", default: {}, null: false
    t.string "source"
    t.string "external_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_type_id", "slug"], name: "index_catalog_entries_on_type_and_slug_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["catalog_type_id"], name: "index_catalog_entries_on_catalog_type_id"
    t.index ["workspace_id", "catalog_type_id"], name: "index_catalog_entries_on_workspace_id_and_catalog_type_id"
    t.index ["workspace_id", "source", "external_id"], name: "index_catalog_entries_external_identity", unique: true, where: "((source IS NOT NULL) AND (external_id IS NOT NULL))"
    t.index ["workspace_id"], name: "index_catalog_entries_on_workspace_id"
  end

  create_table "catalog_entry_relationships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "source_entry_id", null: false
    t.uuid "target_entry_id", null: false
    t.uuid "catalog_attribute_definition_id"
    t.string "relationship_key", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_attribute_definition_id"], name: "idx_on_catalog_attribute_definition_id_77676cd157"
    t.index ["source_entry_id", "catalog_attribute_definition_id"], name: "index_catalog_relationships_single_ref", unique: true, where: "(catalog_attribute_definition_id IS NOT NULL)"
    t.index ["source_entry_id", "target_entry_id", "relationship_key"], name: "index_catalog_relationships_uniqueness", unique: true
    t.index ["source_entry_id"], name: "index_catalog_entry_relationships_on_source_entry_id"
    t.index ["target_entry_id"], name: "index_catalog_entry_relationships_on_target_entry_id"
    t.index ["workspace_id"], name: "index_catalog_entry_relationships_on_workspace_id"
  end

  create_table "catalog_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "kind", null: false
    t.string "system_key"
    t.string "icon"
    t.text "description"
    t.string "color"
    t.integer "position", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "slug"], name: "index_catalog_types_on_workspace_and_slug_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["workspace_id", "system_key"], name: "index_catalog_types_on_workspace_id_and_system_key", unique: true, where: "(system_key IS NOT NULL)"
    t.index ["workspace_id"], name: "index_catalog_types_on_workspace_id"
  end

  create_table "environments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "color"
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_environments_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_environments_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_environments_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_environments_on_workspace_id"
  end

  create_table "idempotency_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "key", null: false
    t.string "resource_type", null: false
    t.uuid "resource_id", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_idempotency_keys_on_created_at"
    t.index ["workspace_id", "resource_type", "key"], name: "idx_on_workspace_id_resource_type_key_0235259f51", unique: true
    t.index ["workspace_id"], name: "index_idempotency_keys_on_workspace_id"
  end

  create_table "incident_action_updates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_action_id", null: false
    t.string "update_type", null: false
    t.string "action_type", null: false
    t.uuid "actor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "incident_id", null: false
    t.uuid "created_by_id", null: false
    t.uuid "assignee_id"
    t.text "description", null: false
    t.string "status", null: false
    t.string "message_ts"
    t.jsonb "platform_data", default: {}, null: false
    t.datetime "deleted_at"
    t.jsonb "changed_fields", default: [], null: false
    t.string "actor_type", null: false
    t.index ["actor_id"], name: "index_incident_action_updates_on_actor_id"
    t.index ["assignee_id"], name: "index_incident_action_updates_on_assignee_id"
    t.index ["created_by_id"], name: "index_incident_action_updates_on_created_by_id"
    t.index ["incident_action_id", "created_at"], name: "idx_on_incident_action_id_created_at_ce446d496c"
    t.index ["incident_action_id"], name: "index_incident_action_updates_on_incident_action_id"
    t.index ["incident_id"], name: "index_incident_action_updates_on_incident_id"
    t.index ["update_type"], name: "index_incident_action_updates_on_update_type"
  end

  create_table "incident_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "created_by_id", null: false
    t.uuid "assignee_id"
    t.string "action_type", default: "action", null: false
    t.text "description", null: false
    t.string "status", default: "open"
    t.string "message_ts"
    t.jsonb "platform_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["assignee_id"], name: "index_incident_actions_on_assignee_id"
    t.index ["deleted_at"], name: "index_incident_actions_on_deleted_at"
    t.index ["incident_id", "action_type"], name: "index_incident_actions_on_incident_id_and_action_type"
    t.index ["incident_id", "status"], name: "index_incident_actions_on_incident_id_and_status"
  end

  create_table "incident_conditions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "conditionable_type", null: false
    t.uuid "conditionable_id", null: false
    t.string "condition_field", null: false
    t.string "operator", null: false
    t.jsonb "values", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "incident_field_definition_id"
    t.index ["conditionable_type", "conditionable_id"], name: "index_incident_conditions_on_conditionable"
    t.index ["incident_field_definition_id"], name: "index_incident_conditions_on_incident_field_definition_id"
    t.index ["workspace_id"], name: "index_incident_conditions_on_workspace_id"
  end

  create_table "incident_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "actor_id"
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.string "eventable_type"
    t.uuid "eventable_id"
    t.string "actor_type"
    t.index ["actor_id"], name: "index_incident_events_on_actor_id"
    t.index ["actor_type", "actor_id"], name: "index_incident_events_on_actor_type_and_actor_id"
    t.index ["event_type"], name: "index_incident_events_on_event_type"
    t.index ["eventable_type", "eventable_id"], name: "index_incident_events_on_eventable_type_and_eventable_id"
    t.index ["incident_id", "created_at"], name: "index_incident_events_on_incident_id_and_created_at"
    t.index ["incident_id"], name: "index_incident_events_on_incident_id"
    t.index ["metadata"], name: "index_incident_events_on_metadata", using: :gin
  end

  create_table "incident_field_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.string "field_type", null: false
    t.string "option_source", null: false
    t.jsonb "config", default: {}, null: false
    t.integer "position", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "key"], name: "index_incident_field_definitions_on_workspace_and_key_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["workspace_id"], name: "index_incident_field_definitions_on_workspace_id"
  end

  create_table "incident_form_fields", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_form_id", null: false
    t.string "field_source_kind", null: false
    t.string "system_field_key"
    t.uuid "incident_field_definition_id"
    t.integer "position", null: false
    t.string "visibility_mode", default: "visible", null: false
    t.string "required_mode", default: "optional", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_field_definition_id"], name: "index_incident_form_fields_on_incident_field_definition_id"
    t.index ["incident_form_id", "field_source_kind", "system_field_key"], name: "index_incident_form_fields_on_form_and_system_field", unique: true, where: "(system_field_key IS NOT NULL)"
    t.index ["incident_form_id", "incident_field_definition_id"], name: "index_incident_form_fields_on_form_and_field_definition", unique: true, where: "(incident_field_definition_id IS NOT NULL)"
    t.index ["incident_form_id"], name: "index_incident_form_fields_on_incident_form_id"
  end

  create_table "incident_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.text "description"
    t.string "lifecycle_event", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "slug"], name: "index_incident_forms_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_forms_on_workspace_id"
  end

  create_table "incident_lifecycle_stages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_incident_lifecycle_stages_on_key", unique: true
    t.index ["position"], name: "index_incident_lifecycle_stages_on_position"
  end

  create_table "incident_relationships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "related_incident_id", null: false
    t.string "relationship_type", null: false
    t.uuid "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_incident_relationships_on_created_by_id"
    t.index ["incident_id", "related_incident_id", "relationship_type"], name: "idx_incident_relationships_unique_pair", unique: true
    t.index ["incident_id"], name: "index_incident_relationships_on_incident_id"
    t.index ["related_incident_id"], name: "index_incident_relationships_on_related_incident_id"
    t.index ["relationship_type"], name: "index_incident_relationships_on_relationship_type"
    t.check_constraint "incident_id <> related_incident_id", name: "chk_no_self_reference"
  end

  create_table "incident_role_assignments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "incident_role_id", null: false
    t.uuid "workspace_membership_id", null: false
    t.datetime "assigned_at", null: false
    t.uuid "assigned_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id", "incident_role_id"], name: "idx_on_incident_id_incident_role_id_9839ecc130", unique: true
    t.index ["incident_id"], name: "index_incident_role_assignments_on_incident_id"
    t.index ["incident_role_id"], name: "index_incident_role_assignments_on_incident_role_id"
    t.index ["workspace_membership_id"], name: "index_incident_role_assignments_on_workspace_membership_id"
  end

  create_table "incident_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_incident_roles_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_incident_roles_on_workspace_id_and_position", unique: true
    t.index ["workspace_id", "slug"], name: "index_incident_roles_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_roles_on_workspace_id"
  end

  create_table "incident_runbooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "runbook_id", null: false
    t.uuid "workspace_id", null: false
    t.uuid "attached_by_id"
    t.datetime "applied_at"
    t.uuid "applied_by_id"
    t.string "message_ts"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["applied_by_id"], name: "index_incident_runbooks_on_applied_by_id"
    t.index ["attached_by_id"], name: "index_incident_runbooks_on_attached_by_id"
    t.index ["incident_id", "runbook_id"], name: "index_incident_runbooks_on_incident_id_and_runbook_id", unique: true
    t.index ["incident_id"], name: "index_incident_runbooks_on_incident_id"
    t.index ["runbook_id"], name: "index_incident_runbooks_on_runbook_id"
    t.index ["workspace_id"], name: "index_incident_runbooks_on_workspace_id"
  end

  create_table "incident_severities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.integer "rank", null: false
    t.integer "position", default: 0, null: false
    t.boolean "is_default", default: false
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_incident_severities_on_deleted_at"
    t.index ["workspace_id", "is_default"], name: "index_incident_severities_on_workspace_id_and_is_default"
    t.index ["workspace_id", "position"], name: "index_incident_severities_on_workspace_id_and_position", unique: true
    t.index ["workspace_id", "rank"], name: "index_incident_severities_on_workspace_id_and_rank"
    t.index ["workspace_id", "slug"], name: "index_incident_severities_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_severities_on_single_default_per_workspace", unique: true, where: "is_default"
    t.index ["workspace_id"], name: "index_incident_severities_on_workspace_id"
  end

  create_table "incident_statuses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.integer "position", default: 0, null: false
    t.boolean "is_default", default: false
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.uuid "incident_lifecycle_stage_id", null: false
    t.index ["deleted_at"], name: "index_incident_statuses_on_deleted_at"
    t.index ["incident_lifecycle_stage_id"], name: "index_incident_statuses_on_incident_lifecycle_stage_id"
    t.index ["workspace_id", "is_default"], name: "index_incident_statuses_on_workspace_id_and_is_default"
    t.index ["workspace_id", "position"], name: "index_incident_statuses_on_workspace_id_and_position", unique: true
    t.index ["workspace_id", "slug"], name: "index_incident_statuses_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_statuses_on_single_default_per_workspace", unique: true, where: "is_default"
    t.index ["workspace_id"], name: "index_incident_statuses_on_workspace_id"
  end

  create_table "incident_summaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "workspace_id", null: false
    t.uuid "inference_id"
    t.text "content", null: false
    t.string "summary_up_to_ts", null: false
    t.datetime "generated_at", null: false
    t.string "model", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_incident_summaries_on_incident_id", unique: true
    t.index ["inference_id"], name: "index_incident_summaries_on_inference_id"
    t.index ["workspace_id", "generated_at"], name: "index_incident_summaries_on_workspace_id_and_generated_at"
    t.index ["workspace_id"], name: "index_incident_summaries_on_workspace_id"
  end

  create_table "incident_transcript_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "incident_id", null: false
    t.string "slack_ts", null: false
    t.string "slack_thread_ts"
    t.string "slack_user_id", null: false
    t.uuid "workspace_membership_id"
    t.text "content", null: false
    t.datetime "posted_at", null: false
    t.boolean "scrubbed", default: false, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id", "posted_at"], name: "idx_on_incident_id_posted_at_8123ad8ebd"
    t.index ["incident_id"], name: "index_incident_transcript_messages_on_incident_id"
    t.index ["workspace_id", "created_at"], name: "idx_on_workspace_id_created_at_8c0e76892b"
    t.index ["workspace_id", "incident_id", "slack_ts"], name: "index_transcript_messages_on_workspace_incident_slack_ts", unique: true
    t.index ["workspace_id", "slack_user_id"], name: "idx_on_workspace_id_slack_user_id_5d5d20d31d"
    t.index ["workspace_id"], name: "index_incident_transcript_messages_on_workspace_id"
    t.index ["workspace_membership_id"], name: "index_incident_transcript_messages_on_workspace_membership_id"
  end

  create_table "incident_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "color"
    t.integer "position", null: false
    t.boolean "is_default", default: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_incident_types_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_incident_types_on_workspace_id_and_position", unique: true
    t.index ["workspace_id", "slug"], name: "index_incident_types_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_types_on_single_default_per_workspace", unique: true, where: "is_default"
    t.index ["workspace_id"], name: "index_incident_types_on_workspace_id"
  end

  create_table "incident_updates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "workspace_id", null: false
    t.uuid "declared_by_id"
    t.uuid "incident_status_id", null: false
    t.uuid "incident_severity_id", null: false
    t.uuid "lead_id"
    t.integer "sequence_number", null: false
    t.string "identifier", null: false
    t.string "name"
    t.text "summary"
    t.boolean "is_private", default: false, null: false
    t.string "channel_id"
    t.string "channel_name"
    t.string "initial_message_ts"
    t.string "announcement_message_ts"
    t.jsonb "platform_data", default: {}, null: false
    t.jsonb "custom_fields", default: {}, null: false
    t.datetime "declared_at", null: false
    t.datetime "resolved_at"
    t.datetime "channel_archived_at"
    t.string "channel_archived_by"
    t.datetime "next_update_at"
    t.datetime "deleted_at"
    t.string "update_type", null: false
    t.uuid "created_by_id"
    t.text "message"
    t.jsonb "changed_fields", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "detected_at"
    t.uuid "incident_type_id"
    t.string "created_by_type"
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
    t.uuid "workspace_id", null: false
    t.uuid "declared_by_id"
    t.uuid "incident_status_id", null: false
    t.uuid "incident_severity_id", null: false
    t.integer "sequence_number", null: false
    t.string "identifier", null: false
    t.string "name"
    t.text "summary"
    t.boolean "is_private", default: false
    t.string "channel_id"
    t.string "channel_name"
    t.string "initial_message_ts"
    t.string "announcement_message_ts"
    t.jsonb "platform_data", default: {}
    t.jsonb "custom_fields", default: {}
    t.datetime "declared_at", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.datetime "channel_archived_at"
    t.string "channel_archived_by"
    t.datetime "next_update_at"
    t.datetime "detected_at"
    t.uuid "incident_type_id"
    t.string "source", null: false
    t.uuid "source_api_key_id"
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

  create_table "inferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.uuid "member_id"
    t.uuid "api_key_id"
    t.string "inferable_type"
    t.uuid "inferable_id"
    t.string "feature", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "cache_read_tokens", default: 0, null: false
    t.integer "cache_write_tokens", default: 0, null: false
    t.integer "cost_micros", default: 0, null: false
    t.integer "latency_ms", default: 0, null: false
    t.string "stop_reason"
    t.string "provider_request_id"
    t.string "status", null: false
    t.string "error_class"
    t.datetime "created_at", null: false
    t.index ["api_key_id"], name: "index_inferences_on_api_key_id"
    t.index ["inferable_type", "inferable_id"], name: "index_inferences_on_inferable"
    t.index ["member_id"], name: "index_inferences_on_member_id"
    t.index ["workspace_id", "created_at"], name: "index_inferences_on_workspace_id_and_created_at"
    t.index ["workspace_id", "feature", "created_at"], name: "index_inferences_on_workspace_id_and_feature_and_created_at"
    t.index ["workspace_id", "inferable_type", "inferable_id"], name: "idx_on_workspace_id_inferable_type_inferable_id_af35668ca4"
    t.index ["workspace_id"], name: "index_inferences_on_workspace_id"
  end

  create_table "integration_environments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "integration_id", null: false
    t.uuid "catalog_entry_id"
    t.text "credentials"
    t.jsonb "base_config", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.string "health_status", default: "unknown", null: false
    t.datetime "health_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "health_error"
    t.index ["integration_id", "catalog_entry_id"], name: "index_integration_environments_on_env", unique: true, where: "(catalog_entry_id IS NOT NULL)"
    t.index ["integration_id"], name: "index_integration_environments_global", unique: true, where: "(catalog_entry_id IS NULL)"
  end

  create_table "integration_tools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "integration_id", null: false
    t.string "name", null: false
    t.string "description"
    t.jsonb "params_schema", default: {}, null: false
    t.jsonb "spec", default: {}, null: false
    t.boolean "read_only", default: false, null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id", "name"], name: "index_integration_tools_on_integration_id_and_name", unique: true
  end

  create_table "integrations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "kind", null: false
    t.string "provider", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "disabled_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "slug"], name: "index_integrations_on_active_slug", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "invite_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "expires_at"
    t.datetime "redeemed_at"
    t.uuid "redeemed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_invite_codes_on_code_digest", unique: true
    t.index ["redeemed_by_id"], name: "index_invite_codes_on_redeemed_by_id"
  end

  create_table "oauth_access_grants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "resource_owner_id", null: false
    t.uuid "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "resource_owner_id", null: false
    t.uuid "application_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.string "scopes"
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "previous_refresh_token", default: "", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret"
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "domain", null: false
    t.string "name", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "domain_config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "scoped_to_type"
    t.uuid "scoped_to_id"
    t.index ["scoped_to_type", "scoped_to_id"], name: "index_policies_on_scoped_to_type_and_scoped_to_id"
    t.index ["workspace_id", "domain", "scoped_to_type", "scoped_to_id", "name"], name: "index_policies_on_scope_and_name", unique: true
    t.index ["workspace_id", "domain"], name: "index_policies_on_workspace_id_and_domain"
    t.index ["workspace_id"], name: "index_policies_on_workspace_id"
  end

  create_table "policy_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "policy_id", null: false
    t.integer "priority", null: false
    t.jsonb "conditions", default: [], null: false
    t.jsonb "outcome", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "enabled", default: true, null: false
    t.index ["policy_id", "priority"], name: "index_policy_rules_on_policy_id_and_priority", unique: true
    t.index ["policy_id"], name: "index_policy_rules_on_policy_id"
  end

  create_table "postmortem_updates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "postmortem_id", null: false
    t.uuid "incident_id", null: false
    t.uuid "edited_by_id", null: false
    t.string "update_type", null: false
    t.string "title", null: false
    t.text "summary"
    t.jsonb "content", default: {}, null: false
    t.string "status", null: false
    t.jsonb "changed_fields", default: [], null: false
    t.string "model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "edited_by_type", null: false
    t.index ["postmortem_id", "created_at"], name: "index_postmortem_updates_on_postmortem_id_and_created_at"
  end

  create_table "postmortems", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "generated_by_id", null: false
    t.string "title", null: false
    t.text "summary"
    t.jsonb "content", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.string "model_id"
    t.string "message_ts"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_postmortems_on_incident_id", unique: true
  end

  create_table "product_areas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "lifecycle_state", default: "active", null: false
    t.integer "tier"
    t.string "color"
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_product_areas_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_product_areas_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_product_areas_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_product_areas_on_workspace_id"
  end

  create_table "runbook_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "runbook_id", null: false
    t.string "title", null: false
    t.text "instruction"
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["runbook_id"], name: "index_runbook_steps_on_runbook_id"
  end

  create_table "runbooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "summary"
    t.text "content"
    t.string "external_url"
    t.integer "position", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "slug"], name: "index_runbooks_on_workspace_id_and_slug_active", unique: true, where: "(deleted_at IS NULL)"
    t.index ["workspace_id"], name: "index_runbooks_on_workspace_id"
  end

  create_table "service_dependencies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "service_id", null: false
    t.uuid "dependency_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dependency_id"], name: "index_service_dependencies_on_dependency_id"
    t.index ["service_id", "dependency_id"], name: "index_service_dependencies_on_service_id_and_dependency_id", unique: true
    t.index ["service_id"], name: "index_service_dependencies_on_service_id"
  end

  create_table "service_environments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "service_id", null: false
    t.uuid "environment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id"], name: "index_service_environments_on_environment_id"
    t.index ["service_id", "environment_id"], name: "index_service_environments_on_service_id_and_environment_id", unique: true
    t.index ["service_id"], name: "index_service_environments_on_service_id"
  end

  create_table "service_product_areas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "service_id", null: false
    t.uuid "product_area_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_area_id"], name: "index_service_product_areas_on_product_area_id"
    t.index ["service_id", "product_area_id"], name: "index_service_product_areas_on_service_id_and_product_area_id", unique: true
    t.index ["service_id"], name: "index_service_product_areas_on_service_id"
  end

  create_table "services", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "lifecycle_state", default: "active", null: false
    t.integer "tier"
    t.string "service_type"
    t.string "language"
    t.string "framework"
    t.string "repo_url"
    t.string "docs_url"
    t.string "runbook_url"
    t.string "alerts_url"
    t.string "dashboard_url"
    t.string "color"
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_services_on_deleted_at"
    t.index ["workspace_id", "position"], name: "index_services_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_services_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_services_on_workspace_id"
  end

  create_table "shoutouts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "incident_id", null: false
    t.uuid "from_member_id", null: false
    t.uuid "to_member_id"
    t.text "message", null: false
    t.string "slack_message_ts"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_shoutouts_on_incident_id"
  end

  create_table "solid_workflow_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.uuid "step_id"
    t.index ["created_at"], name: "index_solid_workflow_events_on_created_at"
    t.index ["event_type"], name: "index_solid_workflow_events_on_event_type"
    t.index ["step_id"], name: "index_solid_workflow_events_on_step_id"
    t.index ["workflow_id", "created_at"], name: "index_workflow_events_on_workflow_and_created_at"
    t.index ["workflow_id"], name: "index_solid_workflow_events_on_workflow_id"
  end

  create_table "solid_workflow_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
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
    t.jsonb "checkpoint"
    t.index ["run_at"], name: "index_solid_workflow_steps_on_run_at"
    t.index ["status", "updated_at"], name: "index_solid_workflow_steps_on_status_and_updated_at"
    t.index ["status"], name: "index_solid_workflow_steps_on_status"
    t.index ["workflow_id", "name"], name: "index_solid_workflow_steps_on_workflow_id_and_name", unique: true
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
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.string "workflow_class", null: false
    t.jsonb "workflow_config", default: {}
    t.jsonb "state_timestamps", default: {}, null: false
    t.datetime "paused_at"
    t.string "paused_by"
    t.text "pause_reason"
    t.datetime "resumed_at"
    t.string "resumed_by"
    t.index ["created_at"], name: "index_solid_workflow_workflows_on_created_at"
    t.index ["state", "updated_at"], name: "index_solid_workflow_workflows_on_state_and_updated_at"
    t.index ["state"], name: "index_solid_workflow_workflows_on_state"
    t.index ["subject_type", "subject_id", "state"], name: "index_workflows_on_subject_and_state"
    t.index ["subject_type", "subject_id"], name: "index_workflows_on_subject"
    t.index ["workflow_class"], name: "index_solid_workflow_workflows_on_workflow_class"
  end

  create_table "team_product_areas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "team_id", null: false
    t.uuid "product_area_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_area_id"], name: "index_team_product_areas_on_product_area_id"
    t.index ["team_id", "product_area_id"], name: "index_team_product_areas_on_team_id_and_product_area_id", unique: true
    t.index ["team_id"], name: "index_team_product_areas_on_team_id"
  end

  create_table "team_services", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "team_id", null: false
    t.uuid "service_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_team_services_on_service_id"
    t.index ["team_id", "service_id"], name: "index_team_services_on_team_id_and_service_id", unique: true
    t.index ["team_id"], name: "index_team_services_on_team_id"
  end

  create_table "teams", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "lifecycle_state", default: "active", null: false
    t.integer "tier"
    t.string "tech_owner"
    t.string "product_owner"
    t.string "color"
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.uuid "webhook_id", null: false
    t.integer "consecutive_failures_count", default: 0, null: false
    t.datetime "first_failure_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["webhook_id"], name: "index_webhook_delinquency_trackers_on_webhook_id", unique: true
  end

  create_table "webhook_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "webhook_id", null: false
    t.uuid "incident_event_id", null: false
    t.string "event_type", null: false
    t.string "state", default: "pending", null: false
    t.jsonb "request_headers", default: {}
    t.jsonb "request_body", default: {}
    t.integer "response_code"
    t.text "error_message"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "signed_payload"
    t.integer "attempts", default: 0, null: false
    t.index ["created_at"], name: "index_webhook_deliveries_on_created_at"
    t.index ["incident_event_id"], name: "index_webhook_deliveries_on_incident_event_id"
    t.index ["state"], name: "index_webhook_deliveries_on_state"
    t.index ["webhook_id", "created_at"], name: "index_webhook_deliveries_on_webhook_id_and_created_at"
    t.index ["webhook_id"], name: "index_webhook_deliveries_on_webhook_id"
  end

  create_table "webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workspace_id", null: false
    t.string "name", null: false
    t.text "url", null: false
    t.string "signing_secret", null: false
    t.jsonb "subscribed_events", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.boolean "archive_channel_enabled", default: true, null: false
    t.integer "archive_channel_delay_minutes", default: 60, null: false
    t.index ["incidents_channel_id"], name: "index_workspaces_on_incidents_channel_id"
    t.index ["platform", "platform_id"], name: "index_workspaces_on_platform_and_platform_id", unique: true
    t.index ["platform"], name: "index_workspaces_on_platform"
  end

  add_foreign_key "ability_actions", "workspaces"
  add_foreign_key "ability_approvals", "workspace_memberships", column: "approver_id"
  add_foreign_key "ability_approvals", "workspaces"
  add_foreign_key "ability_grants", "ability_actions", column: "action_id"
  add_foreign_key "ability_grants", "ability_roles", column: "role_id"
  add_foreign_key "ability_grants", "workspaces"
  add_foreign_key "ability_invocations", "workspaces"
  add_foreign_key "ability_role_actions", "ability_actions", column: "action_id"
  add_foreign_key "ability_role_actions", "ability_roles", column: "role_id"
  add_foreign_key "ability_roles", "workspaces"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agents", "workspaces"
  add_foreign_key "alert_groups", "incidents"
  add_foreign_key "alert_groups", "workspaces"
  add_foreign_key "alert_sources", "workspaces"
  add_foreign_key "alerts", "alert_groups"
  add_foreign_key "alerts", "alert_sources"
  add_foreign_key "alerts", "incidents"
  add_foreign_key "alerts", "policy_rules", column: "matched_policy_rule_id", on_delete: :nullify
  add_foreign_key "alerts", "workspaces"
  add_foreign_key "api_keys", "workspace_memberships"
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
  add_foreign_key "incident_action_updates", "workspace_memberships", column: "assignee_id"
  add_foreign_key "incident_action_updates", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_actions", "incidents"
  add_foreign_key "incident_actions", "workspace_memberships", column: "assignee_id"
  add_foreign_key "incident_actions", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_conditions", "incident_field_definitions"
  add_foreign_key "incident_conditions", "workspaces"
  add_foreign_key "incident_events", "incidents"
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
  add_foreign_key "incident_runbooks", "incidents"
  add_foreign_key "incident_runbooks", "runbooks"
  add_foreign_key "incident_runbooks", "workspace_memberships", column: "applied_by_id"
  add_foreign_key "incident_runbooks", "workspace_memberships", column: "attached_by_id"
  add_foreign_key "incident_runbooks", "workspaces"
  add_foreign_key "incident_severities", "workspaces"
  add_foreign_key "incident_statuses", "incident_lifecycle_stages"
  add_foreign_key "incident_statuses", "workspaces"
  add_foreign_key "incident_summaries", "incidents"
  add_foreign_key "incident_summaries", "inferences"
  add_foreign_key "incident_summaries", "workspaces"
  add_foreign_key "incident_transcript_messages", "incidents"
  add_foreign_key "incident_transcript_messages", "workspace_memberships"
  add_foreign_key "incident_transcript_messages", "workspaces"
  add_foreign_key "incident_types", "workspaces"
  add_foreign_key "incident_updates", "incident_severities"
  add_foreign_key "incident_updates", "incident_statuses"
  add_foreign_key "incident_updates", "incident_types"
  add_foreign_key "incident_updates", "incidents"
  add_foreign_key "incident_updates", "workspace_memberships", column: "declared_by_id"
  add_foreign_key "incident_updates", "workspace_memberships", column: "lead_id"
  add_foreign_key "incident_updates", "workspaces"
  add_foreign_key "incidents", "api_keys", column: "source_api_key_id"
  add_foreign_key "incidents", "incident_severities"
  add_foreign_key "incidents", "incident_statuses"
  add_foreign_key "incidents", "incident_types"
  add_foreign_key "incidents", "workspace_memberships", column: "declared_by_id"
  add_foreign_key "incidents", "workspaces"
  add_foreign_key "inferences", "api_keys"
  add_foreign_key "inferences", "workspace_memberships", column: "member_id"
  add_foreign_key "inferences", "workspaces"
  add_foreign_key "integration_environments", "catalog_entries"
  add_foreign_key "integration_environments", "integrations"
  add_foreign_key "integration_tools", "integrations"
  add_foreign_key "integrations", "workspaces"
  add_foreign_key "invite_codes", "users", column: "redeemed_by_id"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "workspace_memberships", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "workspace_memberships", column: "resource_owner_id"
  add_foreign_key "policies", "workspaces"
  add_foreign_key "policy_rules", "policies"
  add_foreign_key "postmortem_updates", "incidents"
  add_foreign_key "postmortem_updates", "postmortems"
  add_foreign_key "postmortems", "incidents"
  add_foreign_key "postmortems", "workspace_memberships", column: "generated_by_id"
  add_foreign_key "product_areas", "workspaces"
  add_foreign_key "runbook_steps", "runbooks"
  add_foreign_key "runbooks", "workspaces"
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
  add_foreign_key "solid_workflow_events", "solid_workflow_steps", column: "step_id", on_delete: :cascade
  add_foreign_key "solid_workflow_events", "solid_workflow_workflows", column: "workflow_id", on_delete: :cascade
  add_foreign_key "solid_workflow_steps", "solid_workflow_workflows", column: "workflow_id", on_delete: :cascade
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
