class UpgradeRubyLlmTo21 < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:ruby_llm_mcp_credentials)
      create_table :ruby_llm_mcp_credentials, id: :uuid do |t|
        t.references :owner, polymorphic: true, type: :uuid
        t.string :key, null: false
        t.text :data
        t.timestamps

        t.index :key, unique: true
      end
    end

    unless column_exists?(:ruby_llm_tool_calls, :mcp_state)
      if column_exists?(:ruby_llm_tool_calls, :pending_input)
        rename_column :ruby_llm_tool_calls, :pending_input, :mcp_state
      else
        add_column :ruby_llm_tool_calls, :mcp_state, :jsonb
      end
    end

    unless column_exists?(:ruby_llm_tool_calls, :mcp_result)
      add_column :ruby_llm_tool_calls, :mcp_result, :jsonb
    end

    unless column_exists?(:ruby_llm_usages, :server_tool_use)
      add_column :ruby_llm_usages, :server_tool_use, :jsonb
    end

    if columns(:ruby_llm_usages).any? { |column| column.name == "chat_id" && !column.null }
      change_column_null :ruby_llm_usages, :chat_type, true
      change_column_null :ruby_llm_usages, :chat_id, true
    end

    unless column_exists?(:ruby_llm_usages, :owner_id)
      add_reference :ruby_llm_usages, :owner, polymorphic: true, type: :uuid, index: true
    end

    reversible do |direction|
      direction.up do
        operations = check_constraints(:ruby_llm_usages).find { |constraint| constraint.expression.include?("operation") }
        if operations && [ 'chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank', 'judgment', 'video', 'research' ].any? { |operation| !operations.expression.include?("'#{operation}'") }
          remove_check_constraint :ruby_llm_usages, name: operations.name
          add_check_constraint :ruby_llm_usages, "operation::text IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank', 'judgment', 'video', 'research')"
        end
      end
    end

    unless column_exists?(:chat_messages, :cache_ttl)
      add_column :chat_messages, :cache_ttl, :string
    end

    unless table_exists?(:ruby_llm_provider_files)
      create_table :ruby_llm_provider_files, id: :uuid do |t|
        t.string :blob_key, null: false
        t.string :provider, null: false
        t.string :account, null: false
        t.text :file_id, null: false
        t.datetime :expires_at
        t.timestamps

        t.index [ :blob_key, :provider, :account ], unique: true, name: "index_ruby_llm_provider_files_uniqueness"
      end
    end
  end
end
