# Puts a page in the docs store as the daily refresh would, split into chunks, so a test reads documentation without
# the web.
module ProviderDocsHelper
  def store_doc_page(provider:, path:, content:, url: "https://docs.example.com/#{path}", source_key: provider)
    source = ProviderDocSource.find_or_create_by!(key: source_key) { |each| each.provider = provider }
    source.update!(fetched_at: Time.current, checked_at: Time.current)
    page = ProviderDocPage.create!(source: source, provider: provider, path: path, url: url, title: ProviderDocPage.title_for(content, path),
                                   content: content, content_digest: ProviderDocPage.digest_for(content), fetched_at: Time.current)
    page.rechunk!
    page
  end
end
