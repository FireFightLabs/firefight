# A page split at its headings into sections of a few hundred words, each with the headings above it, so a search finds
# the one section that answers. A chunk whose words did not change keeps its embedding, so a refresh embeds only what is
# new.
module ProviderDocPage::Chunking
  extend ActiveSupport::Concern

  MAX_WORDS = 350
  HEADING = /\A(?<level>\#{1,6})\s+(?<text>.+?)\s*#*\s*\z/
  FENCE = /\A\s*(```|~~~)/
  PATH_JOIN = " > ".freeze
  HEADING_PATH_LIMIT = 500

  Piece = Data.define(:heading_path, :text) do
    def digest = Digest::SHA256.hexdigest("#{heading_path}\n#{text}")
  end

  # Each section of the page in order, a long one split between paragraphs.
  def pieces
    sections.flat_map { |heading_path, text| split(text).map { |part| Piece.new(heading_path: heading_path, text: part) } }
  end

  # Writes the page's chunks again, keeping the embedding of every one whose words are unchanged.
  def rechunk!
    kept = chunks.where.not(embedding: nil).to_h { |chunk| [ chunk.content_digest, chunk ] }
    now = Time.current
    rows = pieces.each_with_index.map do |piece, position|
      previous = kept[piece.digest]
      {
        provider_doc_page_id: id, provider: provider, position: position, heading_path: piece.heading_path, text: piece.text,
        content_digest: piece.digest, embedding: previous&.embedding, embedding_model: previous&.embedding_model,
        embedded_digest: previous&.embedded_digest, created_at: now, updated_at: now
      }
    end
    transaction do
      chunks.delete_all
      ProviderDocChunk.insert_all!(rows) if rows.any?
    end
  end

  private

  def sections
    found = []
    trail = []
    lines = []
    fenced = false
    flush = -> { found << [ heading_path(trail), lines.join("\n").strip ] if lines.join.strip.present? }
    content.to_s.sub(ProviderDocPage::FRONT_MATTER, "").each_line(chomp: true) do |line|
      fenced = !fenced if line.match?(FENCE)
      heading = !fenced && line.match(HEADING)
      if heading
        flush.call
        lines = []
        level = heading[:level].size
        trail = trail.reject { |kept_level, _text| kept_level >= level } + [ [ level, heading[:text].strip ] ]
      else
        lines << line
      end
    end
    flush.call
    found
  end

  # The page's title, then each heading above the section, leaving out a top heading that only repeats the title.
  def heading_path(trail)
    headings = trail.map(&:last)
    headings = headings.drop(1) if headings.first&.casecmp?(title)
    [ title, *headings ].join(PATH_JOIN).truncate(HEADING_PATH_LIMIT)
  end

  # Paragraphs gathered up to MAX_WORDS, and a paragraph longer than that, such as a long table or code sample, cut
  # between its lines.
  def split(text)
    parts = text.split(/\n{2,}/).flat_map { |paragraph| words(paragraph) > MAX_WORDS ? by_lines(paragraph) : [ paragraph ] }
    parts.each_with_object([ +"" ]) do |part, gathered|
      gathered << +"" if gathered.last.present? && words(gathered.last) + words(part) > MAX_WORDS
      gathered.last << "\n\n" if gathered.last.present?
      gathered.last << part
    end.reject(&:blank?)
  end

  def by_lines(paragraph)
    paragraph.lines.each_with_object([ +"" ]) do |line, gathered|
      gathered << +"" if gathered.last.present? && words(gathered.last) + words(line) > MAX_WORDS
      gathered.last << line
    end.map(&:rstrip).reject(&:blank?)
  end

  def words(text) = text.to_s.split.size
end
