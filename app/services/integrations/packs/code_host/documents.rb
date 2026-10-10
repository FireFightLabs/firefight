module Integrations
  module Packs
    module CodeHost
      # The text files a handbook page is synced from, one file or the text files in a folder, read from a repository's
      # default branch through the code host's API, so nothing is checked out or run. reader is the host's own
      # Infrastructure reader, which lists a repository's files (listing), reads one (content) and links to it (url).
      class Documents
        File = Data.define(:path, :content, :url)
        # gaps says in words what was left unread, such as a file over the size cap.
        Read = Data.define(:files, :branch, :gaps)

        TEXT = /\.(md|markdown|mdx|txt|rst|adoc)\z/i
        MAX_FILES = 50
        MAX_FILE_BYTES = 200_000

        def initialize(reader)
          @reader = reader
        end

        # path is a file, or a folder whose text files each become a page. A path holding secrets is never read.
        def read(repository, path)
          path = path.to_s.delete_prefix("/")
          raise Integrations::Error, "Firefight does not read files that may hold secrets, so #{path} is not read." if path.match?(SENSITIVE_PATHS)

          listed = @reader.listing(repository)
          wanted = listed.entries.select { |entry| wanted?(entry.path, path) }
          raise Integrations::Error, "#{repository['full_name']} has no text file at #{path} on #{repository['default_branch']}." if wanted.empty?

          gaps = []
          gaps << "The listing of #{repository['full_name']} was cut short, so some files may be missing." if listed.truncated
          gaps << "Only the first #{MAX_FILES} of #{wanted.size} files were read." if wanted.size > MAX_FILES
          files = wanted.sort_by(&:path).first(MAX_FILES).filter_map { |entry| file(repository, entry, gaps) }
          Read.new(files: files, branch: repository["default_branch"], gaps: gaps)
        end

        private

        def wanted?(entry_path, path)
          return false if entry_path.match?(SENSITIVE_PATHS) || entry_path.match?(Infrastructure::SKIPPED)
          return true if entry_path == path

          folder = path.empty? || path.end_with?("/") ? path : "#{path}/"
          entry_path.start_with?(folder) && entry_path.match?(TEXT)
        end

        def file(repository, entry, gaps)
          if entry.size.to_i > MAX_FILE_BYTES
            gaps << "#{entry.path} is over #{MAX_FILE_BYTES / 1000} KB and was not read."
            return
          end

          content = @reader.content(repository, entry).to_s.dup.force_encoding(Encoding::UTF_8).scrub
          File.new(path: entry.path, content: content, url: @reader.url(repository, entry.path))
        rescue Infrastructure::TooLarge
          gaps << "#{entry.path} is over #{MAX_FILE_BYTES / 1000} KB and was not read."
          nil
        end
      end
    end
  end
end
