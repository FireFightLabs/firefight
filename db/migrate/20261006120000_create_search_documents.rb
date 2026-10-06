class CreateSearchDocuments < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_table :search_documents, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.string :searchable_type, null: false
      t.uuid :searchable_id, null: false
      t.string :title, null: false
      # The simple configuration, so an id such as payments-db-2 is kept as written rather than stemmed.
      t.tsvector :document, null: false
      t.text :trigram_text, null: false
      t.jsonb :facets, null: false, default: {}
      t.string :content_digest, null: false
      t.timestamps
    end

    add_index :search_documents, %i[searchable_type searchable_id], unique: true, name: "index_search_documents_on_record"
    add_index :search_documents, %i[workspace_id searchable_type], name: "index_search_documents_on_workspace_and_type"
    add_index :search_documents, :document, using: :gin, name: "index_search_documents_on_document"
    add_index :search_documents, :trigram_text, using: :gin, opclass: :gin_trgm_ops, name: "index_search_documents_on_trigram_text"
  end
end
