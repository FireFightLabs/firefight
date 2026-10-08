# One page of a provider's documentation in the docs store, named by its path within the provider, which is what a
# skill lists under references, with the address it was read from so Halon cites it. The daily refresh writes it, and
# Halon reads it whole through use_skill or read_doc, or finds its sections with search_docs.
class ProviderDocPage < ApplicationRecord
  include Chunking

  FRONT_MATTER = /\A---\n(.*?)\n---\n/m
  TITLE = /^title:\s*["']?(?<title>.+?)["']?\s*$/
  FIRST_HEADING = /^#\s+(?<title>.+?)\s*#*\s*$/

  belongs_to :source, class_name: "ProviderDocSource", foreign_key: :provider_doc_source_id, inverse_of: :pages
  has_many :chunks, class_name: "ProviderDocChunk", foreign_key: :provider_doc_page_id, inverse_of: :page, dependent: :delete_all

  def self.paths_of(provider) = where(provider: provider.to_s).order(:path).pluck(:path)

  def self.named(provider, path) = find_by(provider: provider.to_s, path: path.to_s)

  def self.digest_for(content) = Digest::SHA256.hexdigest(content.to_s)

  # A page's own title, from its front matter or first heading, else its file name.
  def self.title_for(content, path)
    front = content.to_s.match(FRONT_MATTER)&.[](1)
    title = front&.match(TITLE)&.[](:title) || content.to_s.sub(FRONT_MATTER, "").match(FIRST_HEADING)&.[](:title)
    (title.presence || File.basename(path.to_s, ".md").tr("-_", " ").humanize).strip.truncate(250)
  end

  # Said beside the page wherever Halon reads it, so whatever it uses is cited to the page it came from.
  def attribution = "Source: #{title}, #{url}"
end
