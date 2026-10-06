# One row for each resource on the map and each catalog entry, so a person or Halon can find it by its words. The row
# holds what the record said when it was last indexed and is rewritten only when that changes. Memories are never here,
# since their text is encrypted.
class SearchDocument < ApplicationRecord
  belongs_to :workspace
  belongs_to :searchable, polymorphic: true

  TYPES = [ ResourceMap::Resource.name, CatalogEntry.name ].freeze
  WEIGHTS = %w[A B C].freeze
  # A field longer than this says nothing more worth finding, and a provider's details can be long.
  FIELD_LIMIT = 2_000
  BATCH = 500

  # What a record says about itself, field by field, each with its weight: A for its names and ids, B for what describes
  # it, C for what kind of thing it is. The same fields explain why a search found it.
  Field = Data.define(:label, :values, :weight) do
    def text = values.join(" ").first(FIELD_LIMIT)
  end

  def self.class_for(type) = { ResourceMap::Resource.name => ResourceMap::Resource, CatalogEntry.name => CatalogEntry }.fetch(type)

  def self.digest_for(row) = Digest::SHA256.hexdigest(row.to_json)

  # Writes the documents of records, given as one class and its ids. A record that is gone or not worth finding loses
  # its document, and a row whose words have not changed is not rewritten.
  def self.index!(klass, ids)
    ids.uniq.each_slice(BATCH) do |batch|
      records = klass.for_search_documents.where(id: batch).to_a
      klass.prepare_search_documents(records)
      indexable, dropped = records.partition(&:search_document_indexable?)
      gone = batch - records.map(&:id)
      where(searchable_type: klass.name, searchable_id: gone + dropped.map(&:id)).delete_all
      write(indexable.map { |record| row_for(record) }) if indexable.any?
    end
  end

  # Every row in a workspace that holds name as a phrase, or as an environment it runs in.
  def self.naming(workspace_id, name)
    where(workspace_id: workspace_id)
      .where("document @@ phraseto_tsquery('simple', :name) OR facets -> 'environments' ? :name", name: name.to_s)
  end

  # What principal can find for query, a page at a time. See SearchDocument::Search.
  def self.search(workspace, query, principal:, types: nil, filters: {}, limit: Search::DEFAULT_LIMIT, cursor: nil, meaning: nil)
    Search.new(workspace, query, principal: principal, types: types, filters: filters, meaning: meaning).page(limit: limit, cursor: cursor)
  end

  def self.index_later(klass, ids)
    ids = Array(ids).compact.uniq
    SearchDocumentIndexJob.perform_later(klass.name, ids) if ids.any?
  end

  def self.row_for(record)
    fields = record.search_document_fields
    names = record.search_document_names.compact_blank.map { |name| name.to_s.downcase }.uniq
    row = {
      workspace_id: record.workspace_id, searchable_type: record.class.name, searchable_id: record.id,
      title: record.search_document_title,
      weighted: WEIGHTS.to_h { |weight| [ weight, fields.select { |field| field.weight == weight }.map(&:text).join(" ") ] },
      trigram_text: names.join(" "),
      facets: record.search_document_facets.merge(names: names)
    }
    row.merge(content_digest: digest_for(row))
  end
  private_class_method :row_for

  # One statement for a batch. The tsvector is built in the database with the simple configuration, and a row whose
  # digest matches is left as it was, updated_at included.
  def self.write(rows)
    payload = rows.map do |row|
      row.except(:weighted).merge(weight_a: row[:weighted]["A"], weight_b: row[:weighted]["B"], weight_c: row[:weighted]["C"])
    end
    connection.exec_update(sanitize_sql_array([ <<~SQL.squish, payload.to_json ]))
      INSERT INTO search_documents (id, workspace_id, searchable_type, searchable_id, title, document, trigram_text, facets,
                                    content_digest, created_at, updated_at)
      SELECT gen_random_uuid(), doc.workspace_id, doc.searchable_type, doc.searchable_id, doc.title,
             setweight(to_tsvector('simple', coalesce(doc.weight_a, '')), 'A') ||
             setweight(to_tsvector('simple', coalesce(doc.weight_b, '')), 'B') ||
             setweight(to_tsvector('simple', coalesce(doc.weight_c, '')), 'C'),
             doc.trigram_text, doc.facets, doc.content_digest, now(), now()
      FROM jsonb_to_recordset(CAST(? AS jsonb)) AS doc(workspace_id uuid, searchable_type text, searchable_id uuid, title text,
           weight_a text, weight_b text, weight_c text, trigram_text text, facets jsonb, content_digest text)
      ON CONFLICT (searchable_type, searchable_id) DO UPDATE SET
        workspace_id = excluded.workspace_id, title = excluded.title, document = excluded.document,
        trigram_text = excluded.trigram_text, facets = excluded.facets, content_digest = excluded.content_digest,
        updated_at = excluded.updated_at
      WHERE search_documents.content_digest IS DISTINCT FROM excluded.content_digest
    SQL
  end
  private_class_method :write
end
