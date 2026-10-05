module Integrations
  module Packs
    class Github
      # GitHub's side of reading infrastructure as code: a repository's files from its git tree in one call, each file
      # from its blob.
      class Infrastructure < CodeHost::Infrastructure
        HOST = "GitHub".freeze
        PROVIDER = GithubApp::PROVIDER_KEY
        FAILED = GithubApp::Error
        BLOB = "blob".freeze
        BASE64 = "base64".freeze

        def initialize(token)
          super()
          @token = token
        end

        private

        def listing(repository)
          tree = GithubApp.get("/repos/#{repository['full_name']}/git/trees/#{Http.segment(repository['default_branch'])}?recursive=1", token: @token)
          entries = Array(tree["tree"]).select { |entry| entry["type"] == BLOB }.map { |entry| Entry.new(path: entry["path"], size: entry["size"], id: entry["sha"]) }
          Listing.new(entries: entries, truncated: tree["truncated"] == true)
        end

        def content(repository, entry)
          blob = GithubApp.get("/repos/#{repository['full_name']}/git/blobs/#{entry.id}", token: @token)
          blob["encoding"] == BASE64 ? Base64.decode64(blob["content"].to_s) : blob["content"].to_s
        end

        def url(repository, path) = "https://github.com/#{repository['full_name']}/blob/#{Http.segment(repository['default_branch'])}/#{escaped_path(path)}"
      end
    end
  end
end
