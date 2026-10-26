module Integrations
  # What Halon's review of a pull request reads from the code host that holds it, in one shape whichever host that is:
  # the pull request, every file it changes with its diff, and its head checked out in the review's sandbox, where every
  # code tool reads. A code host's pack answers the READ_HOOKS. Its code tools (Packs::CodeHost::Code) answer the
  # sandbox half for every host, and a host only says which repository the head is read from when that is not the
  # pull request's own (review_head_repository). Nothing here names a host.
  module ReviewHost
    STATUS_ADDED = "added".freeze
    STATUS_MODIFIED = "modified".freeze
    STATUS_REMOVED = "removed".freeze
    STATUS_RENAMED = "renamed".freeze
    STATUSES = [ STATUS_ADDED, STATUS_MODIFIED, STATUS_REMOVED, STATUS_RENAMED ].freeze

    STATE_OPEN = PullRequests::OPEN
    STATE_MERGED = PullRequests::MERGED
    STATE_CLOSED = PullRequests::CLOSED

    # Why a changed file is not read, as the review's summary says it.
    LEFT_OUT_BINARY = "a binary file, which has no text to review".freeze
    LEFT_OUT_SECRETS = "it may hold secrets, so Firefight does not read it".freeze
    LEFT_OUT_UNREAD = "its diff could not be read from the code host or the sandbox".freeze

    READ_HOOKS = %i[pull_request_for_review pull_request_files_for_review pull_request_checkout pull_request_sandbox_files pull_request_file_link].freeze

    HUNK = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/
    BINARY = /^Binary files .* differ$|^GIT binary patch$/

    # head_repository is where the head branch lives, the pull request's own repository unless it comes from a fork.
    # merged_at is nil until it merged.
    PullRequest = Data.define(:repository, :number, :title, :body, :author, :url, :state, :draft, :base_ref, :base_sha, :head_ref, :head_sha,
                              :head_repository, :merged_at) do
      def initialize(body: nil, author: nil, draft: false, head_repository: nil, merged_at: nil, **) = super

      def open? = state == STATE_OPEN

      def merged? = state == STATE_MERGED

      def fork? = head_repository.present? && !head_repository.casecmp?(repository)
    end

    # One changed file. patch is its hunks from the first @@, without git's header lines, nil when the host gave none,
    # such as for a file too large to show. previous_path is its name before a rename.
    ChangedFile = Data.define(:path, :previous_path, :status, :additions, :deletions, :patch, :binary) do
      def initialize(previous_path: nil, additions: 0, deletions: 0, patch: nil, binary: false, **) = super
    end

    # Where the sandbox reads the head: a repository, the full commit and every path in it, which is how a finding's
    # code evidence is known to point at a real file.
    Checkout = Data.define(:repository, :ref, :paths) do
      def initialize(paths: [], **) = super

      def holds?(path) = paths.include?(path)
    end

    # One file as the review reads it: the git style diff of it, or why it is left out.
    FileDiff = Data.define(:path, :text, :left_out) do
      def initialize(text: nil, left_out: nil, **) = super

      def read? = left_out.nil?
    end

    module_function

    def reviews?(integration)
      pack = NativePack.for(integration.provider)
      pack.present? && READ_HOOKS.all? { |hook| pack.method_defined?(hook) }
    end

    # The connection rows of the workspace that can review, oldest first.
    def rows(workspace)
      workspace.integrations.active.includes(:integration_environments).select { |integration| integration.holds_code? && reviews?(integration) }
               .flat_map { |integration| integration.integration_environments.select(&:enabled).sort_by(&:created_at) }
    end

    # The connection row that holds repository, as the map knows it, or nil when none here does.
    def row_for(workspace, repository)
      rows(workspace).find { |row| PullRequests.holds?(row, repository) }
    end

    def pull_request(row, repository:, number:)
      pack(row).pull_request_for_review(row, repository: repository, number: number)
    end

    # Every file the pull request changes, as the host lists them. A list the host cuts short is refused.
    def changed_files(row, pull)
      pack(row).pull_request_files_for_review(row, repository: pull.repository, number: pull.number)
    end

    # The head in the sandbox of key, fetched again when the box was given the repository before the head was pushed.
    def checkout!(row, pull, key:)
      pack(row, key).pull_request_checkout(row, pull: pull)
    end

    # The files a commit changes against base_sha, read in the sandbox, for a review of a commit other than the head
    # the host shows now, such as a rehearsal of an earlier round.
    def sandbox_files(row, checkout, base_sha:, key:, path: nil)
      pack(row, key).pull_request_sandbox_files(row, checkout: checkout, base_sha: base_sha, path: path)
    end

    def file_link(row, repository:, sha:, path:, line: nil)
      pack(row).pull_request_file_link(row, repository: repository, sha: sha, path: path, line: line)
    end

    # Every changed file as the review reads it. Files the host gave no text for are read from the sandbox in one go,
    # and one that cannot be read either is left out with why, never dropped without a word.
    def diffs(row, files, checkout:, base_sha:, key:)
      missing = files.select { |file| file.patch.blank? && !file.binary && !secret?(file.path) && !secret?(file.previous_path) }
      read = missing.any? ? sandbox_read(row, checkout, base_sha, key) : {}
      files.map do |file|
        next FileDiff.new(path: file.path, left_out: LEFT_OUT_SECRETS) if secret?(file.path) || secret?(file.previous_path)

        given = missing.include?(file) ? read[file.path] : file
        next FileDiff.new(path: file.path, left_out: LEFT_OUT_UNREAD) unless given
        next FileDiff.new(path: file.path, left_out: LEFT_OUT_BINARY) if given.binary

        FileDiff.new(path: file.path, text: "#{header(file)}#{given.patch.to_s.chomp}#{"\n" if given.patch.present?}")
      end
    end

    # The lines of the new file a comment can sit on, which are those inside a hunk, as ranges.
    def commentable_lines(patch)
      patch.to_s.scan(HUNK).map do |start, count|
        from = start.to_i
        length = count.nil? ? 1 : count.to_i
        from...(from + length)
      end.reject { |range| range.size.zero? }
    end

    # git's own diff output split into changed files, each with its hunks. Used for what the sandbox reads.
    def parse_git_diff(text)
      text.to_s.split(/^(?=diff --git )/).filter_map do |chunk|
        next unless chunk.start_with?("diff --git ")

        lines = chunk.lines
        old_path, new_path = header_paths(lines.first)
        old_path = renamed(lines, "rename from ") || old_path
        new_path = renamed(lines, "rename to ") || new_path
        status = if lines.any? { |line| line.start_with?("new file mode") } then STATUS_ADDED
        elsif lines.any? { |line| line.start_with?("deleted file mode") } then STATUS_REMOVED
        elsif old_path != new_path then STATUS_RENAMED
        else STATUS_MODIFIED
        end
        hunks = lines.drop_while { |line| !line.start_with?("@@") }
        ChangedFile.new(path: new_path, previous_path: (old_path if old_path != new_path), status: status,
                        additions: hunks.count { |line| line.start_with?("+") }, deletions: hunks.count { |line| line.start_with?("-") },
                        patch: hunks.join.presence, binary: lines.any? { |line| line.match?(BINARY) })
      end
    end

    def secret?(path) = path.present? && path.match?(Packs::CodeHost::SENSITIVE_PATHS)

    def header(file)
      before = file.previous_path || file.path
      old_name = file.status == STATUS_ADDED ? "/dev/null" : "a/#{before}"
      new_name = file.status == STATUS_REMOVED ? "/dev/null" : "b/#{file.path}"
      "diff --git a/#{before} b/#{file.path}\n#{"new file\n" if file.status == STATUS_ADDED}#{"deleted file\n" if file.status == STATUS_REMOVED}--- #{old_name}\n+++ #{new_name}\n"
    end

    # The whole change as the sandbox reads it, by path. Empty when the sandbox cannot read it, so its files are left
    # out with why.
    def sandbox_read(row, checkout, base_sha, key)
      sandbox_files(row, checkout, base_sha: base_sha, key: key).index_by(&:path)
    rescue Error => error
      Rails.logger.warn({ event: "review_host.sandbox_unread", integration_id: row.integration_id, error: error.message }.to_json)
      {}
    end

    # "diff --git a/<old> b/<new>", read when both names are the same length, which a rename's own lines correct.
    def header_paths(line)
      rest = line.to_s.chomp.delete_prefix("diff --git ")
      size = (rest.size - 5) / 2
      return [ rest[2, size], rest[(size + 5)..] ] if size.positive? && rest[size, 3] == " b/"

      found = rest.match(%r{\Aa/(.+?) b/(.+)\z})
      found ? [ found[1], found[2] ] : [ rest, rest ]
    end

    def renamed(lines, prefix) = lines.find { |line| line.start_with?(prefix) }&.delete_prefix(prefix)&.chomp

    def pack(row, key = nil) = NativePack.fetch!(row.integration, box_key: key)
  end
end
