module Integrations
  module Packs
    class Gitlab
      # GitLab's side of reading infrastructure as code: a project's files from its repository tree, a page at a time, and
      # each file through the repository files API, whose size is read from its headers before the file is (doc/api/
      # repositories.md and repository_files.md).
      class Infrastructure < CodeHost::Infrastructure
        HOST = "GitLab".freeze
        PROVIDER = Gitlab::PROVIDER_KEY
        FAILED = GitlabApi::Error
        BLOB = "blob".freeze
        SIZE_HEADER = "x-gitlab-size".freeze
        # A tree is listed 100 entries a page, so a very large repository is read in part and says so.
        TREE_PAGES = 50

        def initialize(api)
          super()
          @api = api
        end

        private

        def listing(repository)
          entries, more = @api.list("#{GitlabApi.project(repository['full_name'])}/repository/tree",
                                    { "recursive" => true, "ref" => repository["default_branch"] }, pages: TREE_PAGES)
          blobs = entries.select { |entry| entry["type"] == BLOB }.map { |entry| Entry.new(path: entry["path"], size: nil, id: entry["id"]) }
          Listing.new(entries: blobs, truncated: more)
        end

        def content(repository, entry)
          path = GitlabApi.file(repository["full_name"], entry.path)
          query = { "ref" => repository["default_branch"] }
          raise TooLarge if @api.head(path, query).header(SIZE_HEADER).to_i > MAX_FILE_BYTES

          @api.text("#{path}/raw", query)
        end

        def url(repository, path) = @api.web_url(repository["full_name"], "-", "blob", Http.segment(repository["default_branch"]), escaped_path(path))
      end
    end
  end
end
