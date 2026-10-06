# What a record needs to be found by its words. The record names its title, its fields and its facets, and the rows are
# written in bulk by SearchDocument.index!, never one callback per row of a sweep.
module SearchDocument::Indexing
  extend ActiveSupport::Concern

  included do
    has_one :search_document, as: :searchable, dependent: :delete
  end

  class_methods do
    # The relation index! reads records through, with what their fields need loaded.
    def for_search_documents = all

    # The records that should have a row, which the backfill looks among.
    def search_document_candidates = all

    # Loads what a batch's fields need that a preload cannot reach.
    def prepare_search_documents(_records) = nil
  end

  def search_document_indexable? = true

  def search_document_title = name

  # Names and ids, matched by their fragments and found exactly.
  def search_document_names = [ name ]

  def search_document_facets = {}

  # The labels of the fields that hold any of words, in field order, so a result can say why it was found. A field that
  # says the same as one before it, such as an id that is the name, is not named twice.
  def search_document_matched(words)
    wanted = words.map(&:downcase).compact_blank
    matched = search_document_fields.select { |field| wanted.any? { |word| field.text.downcase.include?(word) } }
    matched.uniq { |field| field.text.downcase }.map(&:label)
  end

  private

  def search_document_field(label, values, weight)
    SearchDocument::Field.new(label: label, values: Array(values).flatten.compact_blank.map(&:to_s).uniq, weight: weight)
  end
end
