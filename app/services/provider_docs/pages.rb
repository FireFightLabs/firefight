module ProviderDocs
  # Reads each page of a site by its address, a page that cannot be read keeping the copy it had. A page too large to
  # read is left out rather than failed, so it does not read as a fault every day.
  module Pages
    def self.read(wanted, client:, revisions:, license:, version: nil)
      failed = {}
      too_large = []
      pages = wanted.filter_map do |path, url|
        answer = client.page(url, revision: revisions[path])
        Fetched.new(path: path, url: url, content: answer.body, revision: answer.revision)
      rescue DocsClient::RateLimited
        raise
      rescue DocsClient::TooLarge
        too_large << path
        nil
      rescue DocsClient::Error => error
        failed[path] = error.message
        nil
      end
      Reading.new(pages: pages, listed: wanted.keys - too_large, failed: failed, version: version, license: license)
    end
  end
end
