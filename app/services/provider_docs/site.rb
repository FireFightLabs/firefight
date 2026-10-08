module ProviderDocs
  # A documentation site's pages, each named in the source list and read as the markdown the site serves for it, asking
  # again only with the revision it answered last, so a page that did not change is not sent twice.
  class Site
    def initialize(definition, client:, revisions:)
      @definition = definition
      @client = client
      @revisions = revisions
    end

    def read
      wanted = @definition.fetch("pages").to_h { |path, page| [ "#{@definition.prefix}#{path}", @definition.page_url(page) ] }
      Pages.read(wanted, client: @client, revisions: @revisions, license: @definition["license"])
    end
  end
end
