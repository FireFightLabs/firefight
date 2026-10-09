module ProviderDocs
  # Reads each page a source lists, a page that cannot be read keeping the copy it had. A page too large to read is left
  # out rather than failed, so it does not read as a fault every day. By default a page is read by its address, and a
  # reader that knows a cheaper way, such as a repository's file hashes, passes a block that answers the Fetched page,
  # with no content when it did not change.
  module Pages
    def self.read(wanted, client:, revisions:, license:, progress:, version: nil, &fetch)
      fetch ||= lambda do |path, url|
        answer = client.page(url, revision: revisions[path])
        Fetched.new(path: path, url: url, content: answer.body, revision: answer.revision)
      end
      failed = {}
      too_large = []
      progress.listed(wanted.size)
      pages = wanted.filter_map do |path, from|
        fetched = fetch.call(path, from)
        progress.page(fetched.content ? :changed : :unchanged)
        fetched
      rescue DocsClient::RateLimited
        raise
      rescue DocsClient::TooLarge
        too_large << path
        progress.page(:left_out)
        nil
      rescue DocsClient::Error => error
        failed[path] = error.message
        progress.page(:failed)
        nil
      end
      Reading.new(pages: pages, listed: wanted.keys - too_large, failed: failed, version: version, license: license)
    end
  end
end
