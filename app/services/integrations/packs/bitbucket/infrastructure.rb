module Integrations
  module Packs
    class Bitbucket
      # Bitbucket's side of reading infrastructure as code: a repository's files from its src listing at the main branch's
      # commit, a page at a time and as deep as max_depth reaches, each with its size, and each file's raw content from
      # the same path (the src path of Bitbucket's OpenAPI description).
      class Infrastructure < CodeHost::Infrastructure
        HOST = "Bitbucket".freeze
        PROVIDER = Bitbucket::PROVIDER_KEY
        FAILED = BitbucketApi::Error
        FILE = "commit_file".freeze
        # How deep the listing reads, and how many pages of 100 entries, so a very large repository is read in part and
        # says so.
        MAX_DEPTH = 20
        LISTING_PAGES = 50

        def initialize(api)
          super()
          @api = api
          @commits = {}
        end

        # What CodeHost::Documents reads a repository's pages through as well.
        def listing(repository)
          name = repository["full_name"]
          head = Array(@api.get("#{BitbucketApi.repository(name)}/commits/#{Http.segment(repository['default_branch'])}", "pagelen" => 1)["values"]).first
          raise FAILED, "#{name} has no commit on #{repository['default_branch']}" unless head

          @commits[name] = head["hash"]
          # The root's listing needs the trailing slash.
          entries, more = @api.list("#{BitbucketApi.repository(name)}/src/#{head['hash']}/", { "max_depth" => MAX_DEPTH }, pages: LISTING_PAGES)
          files = entries.select { |entry| entry["type"] == FILE }.map { |entry| Entry.new(path: entry["path"], size: entry["size"], id: nil) }
          Listing.new(entries: files, truncated: more)
        end

        def content(repository, entry) = @api.text("#{BitbucketApi.repository(repository['full_name'])}/src/#{@commits.fetch(repository['full_name'])}/#{BitbucketApi.path(entry.path)}")

        # Bitbucket gives a file no page address and documents none, so a clue links the repository's own page, which
        # the API gives, and names the file beside it.
        def url(repository, _path) = repository["url"]
      end
    end
  end
end
