# One search across what runs and who owns it: resources on the map, catalog entries and the memories people confirmed.
# Each way of matching ranks its own list, words, a fragment of a name or id, meaning for a catalog entry's description
# and words of a memory, and the lists are merged by reciprocal rank fusion, with an exact name or id always first.
# Nothing outside what principal may read is listed, counted or named.
class SearchDocument::Search
  TYPE_RESOURCE = "resource".freeze
  TYPE_CATALOG_ENTRY = "catalog_entry".freeze
  TYPE_MEMORY = "memory".freeze
  TYPES = [ TYPE_RESOURCE, TYPE_CATALOG_ENTRY, TYPE_MEMORY ].freeze
  RECORD_TYPES = { TYPE_RESOURCE => ResourceMap::Resource.name, TYPE_CATALOG_ENTRY => CatalogEntry.name }.freeze

  DEFAULT_LIMIT = 25
  MAX_LIMIT = 50
  # How far down each list reaches before the lists are merged. Past this a search needs more words, not more pages.
  CANDIDATES = 200
  # The usual constant for reciprocal rank fusion, which keeps one list's first place from drowning out agreement.
  FUSION_K = 60
  # How alike a description has to read to count, so the nearest of an unrelated catalog is not offered as a match. Set
  # from text-embedding-3-small, the default embedding model. In SearchDocument::MeaningFloorTest every answering
  # description scored 0.22 or more and every unrelated one 0.19 or less, and nothing published gives a threshold.
  MEANING_FLOOR = 0.2
  MEANING_CANDIDATES = 20
  # A shorter query is a fragment of a name, which meaning says nothing about.
  MEANING_MIN_LENGTH = 4

  MATCH_EXACT = :exact
  MATCH_WORDS = :words
  MATCH_FRAGMENT = :fragment
  MATCH_MEANING = :meaning
  MATCH_MEMORY = :memory

  # What a matched field is, in the words a result says why it was found.
  FIELD_WORDS = {
    "name" => "its name", "id" => "its provider id", "account" => "its account", "details" => "its details",
    "tags" => "its tags", "catalog" => "a catalog entry it runs", "owners" => "a team that owns it", "kind" => "its kind",
    "provider" => "its provider", "slug" => "its slug", "description" => "what it is for", "attributes" => "its attributes",
    "type" => "its catalog type"
  }.freeze

  InvalidCursor = Class.new(ArgumentError)

  Result = Data.define(:type, :record, :why) do
    def id = record.id

    def title = type == TYPE_MEMORY ? record.text : record.search_document_title

    # The dashboard page that opens it: the map focused on a resource, an entry open in its catalog type, a memory on
    # the Memory page.
    def path
      routes = Rails.application.routes.url_helpers
      case type
      when TYPE_RESOURCE
        routes.resource_map_path(ResourceMap::PAGE_VIEW_PARAM => ResourceMap::VIEW_FOCUS, ResourceMap::PAGE_RESOURCE_PARAM => id)
      when TYPE_CATALOG_ENTRY then routes.catalogue_type_path(record.catalog_type.slug, CatalogEntry::QUERY_PARAM => id)
      when TYPE_MEMORY then routes.memory_path(Chat::Memory::QUERY_PARAM => id)
      end
    end

    def url
      host = ENV["APP_HOST"].presence
      host ? "#{ENV.fetch('APP_PROTOCOL', 'https')}://#{host}#{path}" : path
    end
  end

  # left_out names the types asked for that the reader may not read, so a caller can say so rather than read nothing
  # as no match.
  Page = Data.define(:results, :next_cursor, :left_out)

  attr_reader :workspace, :principal, :query

  # filters are ResourceMap::Query's. Given without types, they narrow the search to resources, since a provider or
  # an owner says nothing about a memory. meaning is called for a vector of the query only when a catalog entry could
  # be found by one, so a search that does not need it costs no model call.
  def initialize(workspace, query, principal:, types: nil, filters: {}, meaning: nil)
    @workspace = workspace
    @query = query.to_s.squish
    @principal = principal
    @filters = filters.to_h.compact_blank
    @asked = types.presence ? types.map(&:to_s) & TYPES : (@filters.any? ? [ TYPE_RESOURCE ] : TYPES)
    @meaning = meaning
  end

  def readable_types = @readable_types ||= @asked.select { |type| readable?(type) }

  def left_out = @asked - readable_types

  def page(limit: DEFAULT_LIMIT, cursor: nil)
    size = limit.to_i.positive? ? [ limit.to_i, MAX_LIMIT ].min : DEFAULT_LIMIT
    offset = decode(cursor)
    ranked = ranking
    shown = ranked[offset, size].to_a
    more = ranked.size > offset + size
    Page.new(results: results_for(shown), next_cursor: (encode(offset + size) if more), left_out: left_out)
  end

  def words
    @words ||= begin
      tokens = @query.downcase.scan(Chat::Memory::Words::TOKEN).uniq
      meaningful = tokens.reject { |token| Chat::Memory::Words::STOP_WORDS.include?(token) }
      meaningful.presence || tokens
    end
  end

  private

  def readable?(type)
    case type
    when TYPE_RESOURCE then principal.may?(Ability::Action::RESOURCE_MAP, Ability::Action::ACTION_READ, workspace)
    when TYPE_CATALOG_ENTRY then principal.may?(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_READ, workspace)
    when TYPE_MEMORY
      Investigation.available_for?(workspace) && principal.may?(Ability::Action::RESOURCE_MEMORY, Ability::Action::ACTION_READ, workspace)
    end
  end

  # Every key found, the best first, each a type and an id, with the ways it matched kept for why.
  def ranking
    @ranking ||= begin
      return [] if words.empty?

      lists = {
        MATCH_EXACT => exact_matches, MATCH_WORDS => word_matches, MATCH_FRAGMENT => fragment_matches,
        MATCH_MEANING => meaning_matches, MATCH_MEMORY => memory_matches
      }
      @matched_by = Hash.new { |hash, key| hash[key] = [] }
      scores = Hash.new(0.0)
      lists.each do |match, keys|
        keys.each_with_index do |key, rank|
          scores[key] += 1.0 / (FUSION_K + rank + 1)
          @matched_by[key] << match
        end
      end
      exact = lists[MATCH_EXACT]
      scores.keys.sort_by { |key| [ exact.index(key) || exact.size, -scores[key], key.last ] }
    end
  end

  def documents
    @documents ||= begin
      parts = []
      if readable_types.include?(TYPE_RESOURCE)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        resources = ResourceMap::Query.new(workspace, within: visible, **@filters).scope
        parts << SearchDocument.where(searchable_type: ResourceMap::Resource.name, searchable_id: resources.select(:id))
      end
      if readable_types.include?(TYPE_CATALOG_ENTRY)
        parts << SearchDocument.where(searchable_type: CatalogEntry.name, searchable_id: workspace.catalog_entries.active.select(:id))
      end
      parts.empty? ? SearchDocument.none : SearchDocument.where(workspace_id: workspace.id).merge(parts.reduce(:or))
    end
  end

  # A name, provider id, slug or account that is exactly the query.
  def exact_matches
    keys(documents.where("search_documents.facets -> 'names' ? :exact", exact: @query.downcase).order(:title).limit(CANDIDATES))
  end

  # Each word, or the start of one, ranked by how densely the words sit in the document, a name above a description.
  def word_matches
    tsquery = words.map { |word| "'#{word.gsub("'", "''")}':*" }.join(" | ")
    relation = documents.where("search_documents.document @@ to_tsquery('simple', :tsquery)", tsquery: tsquery)
                        .order(Arel.sql(SearchDocument.sanitize_sql_array([ "ts_rank_cd(search_documents.document, to_tsquery('simple', ?)) DESC", tsquery ])))
                        .order(:title).limit(CANDIDATES)
    keys(relation)
  end

  # A piece of a name, id or account, or one written a little differently, as trigrams judge it.
  def fragment_matches
    relation = documents.where("? <% search_documents.trigram_text", @query.downcase)
                        .order(Arel.sql(SearchDocument.sanitize_sql_array([ "word_similarity(?, search_documents.trigram_text) DESC", @query.downcase ])))
                        .order(:title).limit(CANDIDATES)
    keys(relation)
  end

  def meaning_matches
    return [] unless @meaning && defined?(FirefightAi) && readable_types.include?(TYPE_CATALOG_ENTRY) && @query.length >= MEANING_MIN_LENGTH
    return [] unless SearchEmbedding.in_workspace(workspace).of_type(CatalogEntry.name).where(model: FirefightAi.embedding_model).exists?

    vector = @meaning.call
    return [] unless vector

    close = SearchEmbedding.nearest(vector, workspace: workspace, limit: MEANING_CANDIDATES, types: [ CatalogEntry.name ])
                           .select { |match| match.similarity.to_f >= MEANING_FLOOR }
    active = workspace.catalog_entries.active.where(id: close.map { |match| match.record.id }).pluck(:id).to_set
    close.select { |match| active.include?(match.record.id) }.map { |match| [ TYPE_CATALOG_ENTRY, match.record.id ] }
  end

  # Memory text is encrypted, so only confirmed memories the reader may see are matched here, in Ruby, as recall does.
  def memory_matches
    return [] unless readable_types.include?(TYPE_MEMORY)

    confirmed = Chat::Memory.visible_to(principal, workspace).where(state: Chat::Memory::STATE_CONFIRMED).to_a
    Chat::Memory.matching(confirmed, @query).first(CANDIDATES).map { |memory| [ TYPE_MEMORY, memory.id ] }
  end

  def keys(relation)
    relation.pluck(:searchable_type, :searchable_id).map { |type, id| [ RECORD_TYPES.key(type), id ] }
  end

  def results_for(shown)
    records = load(shown)
    shown.filter_map do |key|
      record = records[key]
      record && Result.new(type: key.first, record: record, why: why(key, record))
    end
  end

  def load(shown)
    by_type = shown.group_by(&:first).transform_values { |keys| keys.map(&:last) }
    loaded = {}
    if (ids = by_type[TYPE_RESOURCE])
      resources = ResourceMap::Resource.for_search_documents.includes(integration_environment: :environment).where(id: ids).to_a
      ResourceMap::Resource.prepare_search_documents(resources)
      resources.each { |resource| loaded[[ TYPE_RESOURCE, resource.id ]] = resource }
    end
    if (ids = by_type[TYPE_CATALOG_ENTRY])
      CatalogEntry.for_search_documents.where(id: ids).each { |entry| loaded[[ TYPE_CATALOG_ENTRY, entry.id ]] = entry }
    end
    if (ids = by_type[TYPE_MEMORY])
      Chat::Memory.includes(:subject, :confirmed_by).where(id: ids).each { |memory| loaded[[ TYPE_MEMORY, memory.id ]] = memory }
    end
    loaded
  end

  # A sentence on how it matched, from the fields that hold the words.
  def why(key, record)
    matched = @matched_by[key]
    return memory_why(record) if key.first == TYPE_MEMORY

    fields = record.search_document_matched(words)
    if matched.include?(MATCH_EXACT)
      exact = record.search_document_fields.find { |field| field.values.any? { |value| value.downcase == @query.downcase } }
      return "Exactly #{FIELD_WORDS.fetch(exact&.label, 'its name')}."
    end
    parts = []
    parts << "Matches #{fields.map { |field| FIELD_WORDS.fetch(field, field) }.to_sentence}" if fields.any?
    parts << "Close to its name or id" if fields.empty? && matched.include?(MATCH_FRAGMENT)
    parts << "What it is for reads like the search" if matched.include?(MATCH_MEANING)
    "#{parts.join('. ')}."
  end

  def memory_why(memory)
    memory.about ? "A confirmed memory about #{memory.about} holds these words." : "A confirmed memory holds these words."
  end

  # The offset into the ranking, tied to this query, its types and filters, so a cursor from another search is refused.
  def encode(offset) = Base64.urlsafe_encode64([ offset, fingerprint ].to_json, padding: false)

  def decode(cursor)
    return 0 if cursor.blank?

    offset, print = read(cursor)
    raise InvalidCursor, "This cursor belongs to another search. Pass the same query, types and filters it came with." unless print == fingerprint
    raise InvalidCursor, "This cursor is not one a page gave." unless offset.is_a?(Integer) && offset >= 0

    offset
  end

  def read(cursor)
    parsed = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
    parsed.is_a?(Array) ? parsed : []
  rescue ArgumentError, JSON::ParserError
    raise InvalidCursor, "This cursor is not one a page gave."
  end

  def fingerprint = Digest::SHA256.hexdigest([ @query.downcase, @asked.sort, @filters.to_a.map { |key, value| [ key.to_s, value.respond_to?(:id) ? value.id : value ] } ].to_json).first(16)
end
