module Integrations
  module Packs
    class AzureDevops
      # Azure Repos' side of reading infrastructure as code: a repository's files listed in one read of its tree at the
      # default branch (Items - List, recursionLevel Full), and each file's content from the same API (Items - Get,
      # includeContent). The listing gives no sizes, so a file is measured once read and left out past the cap.
      class Infrastructure < CodeHost::Infrastructure
        HOST = "Azure DevOps".freeze
        PROVIDER = AzureDevops::PROVIDER_KEY
        FAILED = AzureDevopsApi::Error
        BLOB = "blob".freeze

        def initialize(api)
          super()
          @api = api
        end

        # What CodeHost::Documents reads a repository's pages through as well.
        def listing(repository)
          items = @api.values(@api.get("#{path(repository)}/items", "scopePath" => "/", "recursionLevel" => "Full", **version(repository)))
          files = items.select { |item| item["gitObjectType"] == BLOB && !item["isFolder"] }.map { |item| Entry.new(path: item["path"].to_s.delete_prefix("/"), size: nil, id: item["objectId"]) }
          Listing.new(entries: files, truncated: false)
        end

        def content(repository, entry)
          item = @api.get("#{path(repository)}/items", "path" => "/#{entry.path}", "includeContent" => true, "$format" => "json", **version(repository))
          text = item["content"].to_s
          raise TooLarge if text.bytesize > MAX_FILE_BYTES

          text
        end

        # Microsoft documents no address of one file's page, so a clue links the repository's own page, which the API gives
        # as its webUrl, and names the file beside it.
        def url(repository, _path) = repository["url"]

        private

        def path(repository) = AzureDevopsApi.repository(*repository["full_name"].split("/", 2))

        def version(repository) = { "versionDescriptor.version" => repository["default_branch"], "versionDescriptor.versionType" => "branch" }
      end
    end
  end
end
