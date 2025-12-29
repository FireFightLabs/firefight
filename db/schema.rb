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

ActiveRecord::Schema[8.1].define(version: 2025_12_15_092821) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

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
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.string "workflow_class", null: false
    t.jsonb "workflow_config", default: {}
    t.index ["created_at"], name: "index_workflows_on_created_at"
    t.index ["state", "updated_at"], name: "index_workflows_on_state_and_updated_at"
    t.index ["state"], name: "index_workflows_on_state"
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
    t.datetime "installed_at", null: false
    t.string "name", null: false
    t.string "platform", default: "slack", null: false
    t.jsonb "platform_data", default: {}, null: false
    t.string "platform_id", null: false
    t.text "refresh_token"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["platform", "platform_id"], name: "index_workspaces_on_platform_and_platform_id", unique: true
    t.index ["platform"], name: "index_workspaces_on_platform"
  end

  add_foreign_key "workflow_events", "workflow_steps"
  add_foreign_key "workflow_events", "workflows"
  add_foreign_key "workflow_steps", "workflows"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
end
