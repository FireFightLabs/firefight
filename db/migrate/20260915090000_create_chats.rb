class CreateChats < ActiveRecord::Migration[8.1]
  def change
    # RubyLLM's model registry, filled by RubyLLM the first time a chat resolves a model.
    create_table :ruby_llm_models, id: :uuid do |t|
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :provider, null: false
      t.string :family
      t.datetime :model_created_at
      t.integer :context_window
      t.integer :max_output_tokens
      t.date :knowledge_cutoff
      t.datetime :unlisted_at
      t.jsonb :modalities, default: {}
      t.jsonb :capabilities, default: []
      t.jsonb :pricing, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :ruby_llm_models, [ :provider, :model_id ], unique: true
    add_index :ruby_llm_models, :provider
    add_index :ruby_llm_models, :family

    create_table :chats, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :owner, type: :uuid, polymorphic: true, null: false, index: { unique: true }
      t.references :ruby_llm_model, type: :uuid, foreign_key: true
      t.boolean :cancelled, null: false, default: false
      t.timestamps
    end

    create_table :chat_messages, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: true, index: false
      t.string :role, null: false
      t.text :content
      t.boolean :cache_until_here, null: false, default: false
      t.text :thinking_text
      t.text :thinking_signature
      t.jsonb :citations
      t.jsonb :server_tool_calls
      t.jsonb :raw_content
      t.jsonb :raw_reasoning
      t.string :finish_reason
      t.timestamps
    end
    add_index :chat_messages, [ :chat_id, :created_at ]

    create_table :ruby_llm_tool_calls, id: :uuid do |t|
      t.references :message, type: :uuid, polymorphic: true, null: false, index: false
      t.references :result, type: :uuid, polymorphic: true, index: false
      t.string :tool_call_id, null: false
      t.string :name, null: false
      t.text :thought_signature
      t.string :approval
      t.boolean :remote, null: false, default: false
      t.jsonb :arguments, default: {}
      t.timestamps
    end
    # Unique per message, not globally as RubyLLM installs it, since a model that numbers
    # its calls would otherwise fail another workspace's run.
    add_index :ruby_llm_tool_calls, [ :message_type, :message_id, :tool_call_id ], unique: true,
              name: "index_ruby_llm_tool_calls_on_message_and_tool_call_id"
    add_index :ruby_llm_tool_calls, [ :result_type, :result_id ]
    add_index :ruby_llm_tool_calls, :name

    create_table :ruby_llm_usages, id: :uuid do |t|
      t.references :chat, type: :uuid, polymorphic: true, null: false, index: false
      t.references :message, type: :uuid, polymorphic: true, index: false
      t.string :operation, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.string :status, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.integer :cache_write_tokens
      t.integer :thinking_tokens
      t.decimal :input_cost, precision: 16, scale: 10
      t.decimal :output_cost, precision: 16, scale: 10
      t.decimal :cache_read_cost, precision: 16, scale: 10
      t.decimal :cache_write_cost, precision: 16, scale: 10
      t.decimal :thinking_cost, precision: 16, scale: 10
      t.decimal :total_cost, precision: 16, scale: 10
      t.timestamps
    end
    add_index :ruby_llm_usages, [ :chat_type, :chat_id ]
    add_index :ruby_llm_usages, [ :message_type, :message_id ]
    add_index :ruby_llm_usages, :status
  end
end
