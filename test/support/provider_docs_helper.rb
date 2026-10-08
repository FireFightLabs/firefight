# Lets a test read documentation without the web, through a fake web or a page put straight into the docs store.
module ProviderDocsHelper
  # Answers like the web would, from a table of address to text. An address answering :gone is a 404, :down cannot be
  # reached, and :unchanged a 304 for the revision it was asked with.
  class FakeWeb
    attr_reader :asked

    def initialize(answers)
      @answers = answers
      @asked = []
    end

    def page(url, revision: nil) = answer(url, revision)

    def file(url, revision: nil, headers: {}) = answer(url, revision)

    def json(url, headers: {}) = JSON.parse(answer(url, nil).body)

    private

    def answer(url, revision)
      @asked << url
      found = @answers.fetch(url) { raise DocsClient::NotFound, "#{url} answered 404" }
      raise DocsClient::NotFound, "#{url} answered 404" if found == :gone
      raise DocsClient::Error, "could not reach #{URI.parse(url).host}" if found == :down
      raise DocsClient::TooLarge, "#{url} is larger than 3 MB" if found == :huge
      return DocsClient::Answer.new(body: nil, revision: revision, url: url) if found == :unchanged

      DocsClient::Answer.new(body: found, revision: "\"#{Digest::SHA1.hexdigest(found)}\"", url: url)
    end
  end

  # Puts a page in the docs store as the daily refresh would, split into chunks.
  def store_doc_page(provider:, path:, content:, url: "https://docs.example.com/#{path}", source_key: provider)
    source = ProviderDocSource.find_or_create_by!(key: source_key) { |each| each.provider = provider }
    source.update!(fetched_at: Time.current, checked_at: Time.current)
    page = ProviderDocPage.create!(source: source, provider: provider, path: path, url: url, title: ProviderDocPage.title_for(content, path),
                                   content: content, content_digest: ProviderDocPage.digest_for(content), fetched_at: Time.current)
    page.rechunk!
    page
  end
end
