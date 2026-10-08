# A page split at its headings, so a search hands Halon the few sections that answer rather than whole pages. Each is
# found by its words (document, generated from the heading path and text) and by its meaning (embedding, written only
# when its text changed).
class CreateProviderDocChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_doc_chunks, id: :uuid do |t|
      t.references :provider_doc_page, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :provider, null: false
      t.integer :position, null: false
      t.string :heading_path, null: false
      t.text :text, null: false
      t.string :content_digest, null: false
      t.virtual :document, type: :tsvector, stored: true,
                           as: "to_tsvector('simple'::regconfig, (heading_path::text || ' '::text) || text)"
      t.vector :embedding, limit: 1536
      t.string :embedding_model
      t.string :embedded_digest
      t.timestamps
      t.index [ :provider_doc_page_id, :position ], unique: true
      t.index :provider
      t.index :document, using: :gin
      t.index :embedding, using: :hnsw, opclass: :vector_cosine_ops
    end
  end
end
