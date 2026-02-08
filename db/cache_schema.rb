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

ActiveRecord::Schema[8.1].define(version: 2026_02_04_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "incident_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_type", default: "action", null: false
    t.uuid "assignee_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "deleted_at"
    t.text "description", null: false
    t.uuid "incident_id", null: false
    t.jsonb "platform_data", default: {}
    t.string "slack_message_ts"
    t.string "status", default: "open"
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_incident_actions_on_assignee_id"
    t.index ["deleted_at"], name: "index_incident_actions_on_deleted_at"
    t.index ["incident_id", "action_type"], name: "index_incident_actions_on_incident_id_and_action_type"
    t.index ["incident_id", "status"], name: "index_incident_actions_on_incident_id_and_status"
  end

  create_table "incident_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.uuid "incident_id", null: false
    t.jsonb "metadata", default: {}
    t.uuid "user_id"
    t.index ["event_type"], name: "index_incident_events_on_event_type"
    t.index ["incident_id", "created_at"], name: "index_incident_events_on_incident_id_and_created_at"
    t.index ["incident_id"], name: "index_incident_events_on_incident_id"
    t.index ["metadata"], name: "index_incident_events_on_metadata", using: :gin
    t.index ["user_id"], name: "index_incident_events_on_user_id"
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
    t.string "category", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["deleted_at"], name: "index_incident_statuses_on_deleted_at"
    t.index ["workspace_id", "category"], name: "index_incident_statuses_on_workspace_id_and_category"
    t.index ["workspace_id", "is_default"], name: "index_incident_statuses_on_workspace_id_and_is_default"
    t.index ["workspace_id", "position"], name: "index_incident_statuses_on_workspace_id_and_position"
    t.index ["workspace_id", "slug"], name: "index_incident_statuses_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_incident_statuses_on_workspace_id"
  end

  create_table "incidents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "announcement_message_ts"
    t.datetime "created_at", null: false
    t.jsonb "custom_fields", default: {}
    t.datetime "declared_at", null: false
    t.uuid "declared_by_id", null: false
    t.datetime "deleted_at"
    t.string "identifier", null: false
    t.uuid "incident_severity_id", null: false
    t.uuid "incident_status_id", null: false
    t.string "initial_message_ts"
    t.boolean "is_private", default: false
    t.string "name"
    t.jsonb "platform_data", default: {}
    t.datetime "resolved_at"
    t.integer "sequence_number", null: false
    t.string "slack_channel_id"
    t.string "slack_channel_name"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["declared_at"], name: "index_incidents_on_declared_at"
    t.index ["declared_by_id"], name: "index_incidents_on_declared_by_id"
    t.index ["incident_severity_id"], name: "index_incidents_on_incident_severity_id"
    t.index ["incident_status_id"], name: "index_incidents_on_incident_status_id"
    t.index ["workspace_id", "deleted_at"], name: "index_incidents_on_workspace_id_and_deleted_at"
    t.index ["workspace_id", "identifier"], name: "index_incidents_on_workspace_id_and_identifier", unique: true
    t.index ["workspace_id", "incident_status_id"], name: "index_incidents_on_workspace_id_and_incident_status_id"
    t.index ["workspace_id", "sequence_number"], name: "index_incidents_on_workspace_id_and_sequence_number", unique: true
    t.index ["workspace_id"], name: "index_incidents_on_workspace_id"
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

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "workflow_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.uuid "workflow_step_id"
    t.index ["created_at"], name: "index_workflow_events_on_created_at"
    t.index ["event_type"], name: "index_workflow_events_on_event_type"
    t.index ["workflow_id", "created_at"], name: "index_workflow_events_on_workflow_and_created_at"
    t.index ["workflow_id"], name: "index_workflow_events_on_workflow_id"
    t.index ["workflow_step_id"], name: "index_workflow_events_on_workflow_step_id"
  end

  create_table "workflow_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["run_at"], name: "index_workflow_steps_on_run_at"
    t.index ["status", "updated_at"], name: "index_workflow_steps_on_status_and_updated_at"
    t.index ["status"], name: "index_workflow_steps_on_status"
    t.index ["workflow_id", "name"], name: "index_workflow_steps_on_workflow_id_and_name"
    t.index ["workflow_id", "status"], name: "index_workflow_steps_on_workflow_id_and_status"
    t.index ["workflow_id"], name: "index_workflow_steps_on_workflow_id"
  end

  create_table "workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["created_at"], name: "index_workflows_on_created_at"
    t.index ["state", "updated_at"], name: "index_workflows_on_state_and_updated_at"
    t.index ["state"], name: "index_workflows_on_state"
    t.index ["subject_type", "subject_id", "state"], name: "index_workflows_on_subject_and_state"
    t.index ["subject_type", "subject_id"], name: "index_workflows_on_subject"
    t.index ["workflow_class"], name: "index_workflows_on_workflow_class"
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
    t.index ["incidents_channel_id"], name: "index_workspaces_on_incidents_channel_id"
    t.index ["platform", "platform_id"], name: "index_workspaces_on_platform_and_platform_id", unique: true
    t.index ["platform"], name: "index_workspaces_on_platform"
  end

  add_foreign_key "incident_actions", "incidents"
  add_foreign_key "incident_actions", "workspace_memberships", column: "assignee_id"
  add_foreign_key "incident_actions", "workspace_memberships", column: "created_by_id"
  add_foreign_key "incident_events", "incidents"
  add_foreign_key "incident_events", "workspace_memberships", column: "user_id"
  add_foreign_key "incident_role_assignments", "incident_roles"
  add_foreign_key "incident_role_assignments", "incidents"
  add_foreign_key "incident_role_assignments", "workspace_memberships"
  add_foreign_key "incident_role_assignments", "workspace_memberships", column: "assigned_by_id"
  add_foreign_key "incident_roles", "workspaces"
  add_foreign_key "incident_severities", "workspaces"
  add_foreign_key "incident_statuses", "workspaces"
  add_foreign_key "incidents", "incident_severities"
  add_foreign_key "incidents", "incident_statuses"
  add_foreign_key "incidents", "workspace_memberships", column: "declared_by_id"
  add_foreign_key "incidents", "workspaces"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "workflow_events", "workflow_steps"
  add_foreign_key "workflow_events", "workflows"
  add_foreign_key "workflow_steps", "workflows"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
end
