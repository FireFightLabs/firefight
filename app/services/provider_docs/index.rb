module ProviderDocs
  # A documentation site that lists its markdown pages in an index, such as Northflank's llms.txt. Every link under the
  # source's address that ends in its suffix is a page, so a page the site adds is read the next day and one it drops is
  # removed.
  class Index
    LINK = /\]\((?<url>https:[^)\s]+)\)/

    def initialize(definition, client:, revisions:)
      @definition = definition
      @client = client
      @revisions = revisions
    end

    def read
      under = @definition.fetch("under")
      suffix = @definition.fetch("suffix")
      links = @client.page(@definition.address).body.scan(LINK).flatten.map { |url| url.split("#").first }.uniq
      wanted = links.select { |url| url.start_with?(under) && url.end_with?(suffix) }.to_h do |url|
        [ "#{@definition.prefix}#{url.delete_prefix(under).delete_suffix(suffix)}.md", url ]
      end
      raise DocsClient::Error, "#{@definition.address} lists no pages under #{under}" if wanted.empty?

      Pages.read(wanted, client: @client, revisions: @revisions, license: @definition["license"])
    end
  end
end
