class AddSimilaritySearch < ActiveRecord::Migration[8.1]
  # Whatever writes an embedding must produce this many numbers, so the model that writes them is
  # configured on its own and a change means re-embedding.
  DIMENSIONS = 1536

  def change
    enable_extension "vector"

    create_table :search_embeddings, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :embeddable, type: :uuid, polymorphic: true, null: false, index: false
      t.string :model, null: false
      # What was embedded, so a record whose text has not changed is not embedded twice.
      t.string :content_digest, null: false
      t.column :vector, "vector(#{DIMENSIONS})", null: false
      t.timestamps
    end
    add_index :search_embeddings, [ :embeddable_type, :embeddable_id ], unique: true,
              name: "index_search_embeddings_on_embeddable"
    add_index :search_embeddings, :vector, using: :hnsw, opclass: :vector_cosine_ops
  end
end
