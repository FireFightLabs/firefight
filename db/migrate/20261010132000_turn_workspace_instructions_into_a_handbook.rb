class TurnWorkspaceInstructionsIntoAHandbook < ActiveRecord::Migration[8.1]
  ONE_PER_PLACE = "index_chat_instructions_one_current_per_place".freeze
  NO_SCOPE = "'00000000-0000-0000-0000-000000000000'::uuid".freeze
  HANDBOOK_KEYS = %w[handbook.read handbook.create handbook.update handbook.delete].freeze

  def up
    # Where synced handbook pages come from, a repository's file or folder or a document in a connected tool.
    create_table :chat_handbook_sources, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :integration, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :repository
      t.string :path
      t.string :reference
      t.string :url
      t.string :branch
      t.string :digest
      t.datetime :synced_at
      t.text :sync_error
      t.references :added_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
    end

    create_table :chat_handbook_pages, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.text :title, null: false
      t.string :kind, null: false
      t.integer :position, null: false
      t.references :source, type: :uuid, foreign_key: { to_table: :chat_handbook_sources, on_delete: :cascade }
      t.string :source_path
      t.string :source_url
      t.timestamps
      t.index %i[workspace_id position], unique: true
    end
    # One page says who directs Halon.
    add_index :chat_handbook_pages, :workspace_id, unique: true, where: "kind = 'directing'", name: "index_chat_handbook_pages_one_directing"

    add_reference :chat_instructions, :handbook_page, type: :uuid, foreign_key: { to_table: :chat_handbook_pages, on_delete: :cascade }
    # The page saying who directs Halon in an incident names a role.
    add_reference :chat_instructions, :incident_role, type: :uuid, foreign_key: { on_delete: :nullify }
    # The freeze windows a page sets, which plans keep out of (Workspace::FreezeWindows).
    add_column :chat_instructions, :freeze_windows, :jsonb, null: false, default: []

    # What the workspace wrote for itself before the handbook becomes its first page, with its history.
    execute <<~SQL.squish
      INSERT INTO chat_handbook_pages (id, workspace_id, title, kind, position, created_at, updated_at)
      SELECT gen_random_uuid(), workspace_id, 'General', 'written', 1, now(), now()
      FROM chat_instructions WHERE scope_type IS NULL GROUP BY workspace_id
    SQL
    execute <<~SQL.squish
      UPDATE chat_instructions SET handbook_page_id = chat_handbook_pages.id
      FROM chat_handbook_pages WHERE chat_instructions.scope_type IS NULL AND chat_handbook_pages.workspace_id = chat_instructions.workspace_id
    SQL

    remove_index :chat_instructions, name: ONE_PER_PLACE
    add_index :chat_instructions, "workspace_id, COALESCE(scope_type, ''), COALESCE(scope_id, #{NO_SCOPE})",
              unique: true, where: "superseded_at IS NULL AND handbook_page_id IS NULL", name: ONE_PER_PLACE
    add_index :chat_instructions, :handbook_page_id, unique: true, where: "superseded_at IS NULL", name: "index_chat_instructions_one_current_per_page"
    add_check_constraint :chat_instructions, "(scope_type IS NULL) = (handbook_page_id IS NOT NULL)", name: "chat_instructions_page_only_in_the_handbook"

    # Each page split into sections for search, by words and by meaning. The words are kept without their positions, so
    # the index cannot be read back into the page, whose text is encrypted.
    create_table :chat_handbook_chunks, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :handbook_page, type: :uuid, null: false, foreign_key: { to_table: :chat_handbook_pages, on_delete: :cascade }, index: false
      t.integer :position, null: false
      t.text :heading_path, null: false
      t.text :text, null: false
      t.string :content_digest, null: false
      t.tsvector :document, null: false
      t.vector :embedding, limit: 1536
      t.string :embedding_model
      t.string :embedded_digest
      t.timestamps
      t.index %i[handbook_page_id position], unique: true
      t.index :document, using: :gin
      t.index :embedding, using: :hnsw, opclass: :vector_cosine_ops
    end

    # Who wrote each message in a chat several people speak in, so Halon can tell them apart.
    add_reference :chat_messages, :sender, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }

    create_table :chat_handbook_proposals, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      # The page it changes, or nil for a new page.
      t.references :handbook_page, type: :uuid, foreign_key: { to_table: :chat_handbook_pages, on_delete: :cascade }
      t.text :title
      # The wording the proposal would replace, so accepting it after someone else edited the page is refused.
      t.references :instruction, type: :uuid, foreign_key: { to_table: :chat_instructions, on_delete: :nullify }
      t.text :text, null: false
      t.text :evidence, null: false
      t.references :conversation, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :investigation, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :incident, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :channel_id
      t.string :thread_id
      t.string :message_id
      t.string :status, null: false, default: "pending"
      t.boolean :edited, null: false, default: false
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :decided_at
      t.references :result, type: :uuid, foreign_key: { to_table: :chat_instructions, on_delete: :nullify }
      t.datetime :told_at
      t.timestamps
      t.index %i[workspace_id status]
    end

    # The handbook's own permission, listed in the grant picker from these rows. Firefight's investigator reads it in a
    # run, through an ordinary grant an admin can revoke.
    values = HANDBOOK_KEYS.map do |key|
      risk = key.end_with?(".read") ? "read" : key.end_with?(".delete") ? "destructive" : "write"
      "(gen_random_uuid(), '#{key}', 'system', '#{risk}', #{risk != 'destructive'}, '{}', now(), now())"
    end
    execute <<~SQL.squish
      INSERT INTO ability_actions (id, key, kind, risk_level, reversible, params_schema, created_at, updated_at)
      VALUES #{values.join(', ')}
      ON CONFLICT (key) WHERE workspace_id IS NULL DO NOTHING
    SQL
    execute <<~SQL.squish
      INSERT INTO system_agents (id, slug, name, created_at, updated_at)
      VALUES (gen_random_uuid(), 'investigator', 'Firefight Investigator', now(), now())
      ON CONFLICT (slug) DO NOTHING
    SQL
    execute <<~SQL.squish
      INSERT INTO ability_grants (id, workspace_id, principal_type, principal_id, action_id, scope, created_at, updated_at)
      SELECT gen_random_uuid(), workspaces.id, 'SystemAgent', system_agents.id, ability_actions.id, '{}', now(), now()
      FROM workspaces CROSS JOIN system_agents CROSS JOIN ability_actions
      WHERE system_agents.slug = 'investigator' AND ability_actions.key = 'handbook.read' AND ability_actions.workspace_id IS NULL
      ON CONFLICT (workspace_id, principal_type, principal_id, action_id) WHERE action_id IS NOT NULL DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM ability_actions WHERE workspace_id IS NULL AND key IN (#{HANDBOOK_KEYS.map { |key| "'#{key}'" }.join(', ')})"
    drop_table :chat_handbook_proposals
    remove_reference :chat_messages, :sender
    drop_table :chat_handbook_chunks
    remove_check_constraint :chat_instructions, name: "chat_instructions_page_only_in_the_handbook"
    remove_index :chat_instructions, name: "index_chat_instructions_one_current_per_page"
    remove_index :chat_instructions, name: ONE_PER_PLACE
    execute "UPDATE chat_instructions SET handbook_page_id = NULL"
    remove_column :chat_instructions, :freeze_windows
    remove_reference :chat_instructions, :incident_role
    remove_reference :chat_instructions, :handbook_page
    drop_table :chat_handbook_pages
    drop_table :chat_handbook_sources
    add_index :chat_instructions, "workspace_id, COALESCE(scope_type, ''), COALESCE(scope_id, #{NO_SCOPE})",
              unique: true, where: "superseded_at IS NULL", name: ONE_PER_PLACE
  end
end
