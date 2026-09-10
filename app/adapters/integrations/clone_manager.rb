require "open3"

module Integrations
  # Repo content is untrusted, so git runs with hooks and prompts off and arguments as arrays,
  # never a shell. The installation token rides a per-call header, never the clone's config.
  class CloneManager
    class Error < Integrations::Error; end

    STALE_AFTER = 5.minutes

    BlameLine = Data.define(:line, :sha, :author, :date, :summary)

    class << self
      def clone_limit
        (ENV["REPO_CLONE_LIMIT"].presence || 20).to_i
      end

      def root
        Pathname.new(ENV["REPO_CLONE_ROOT"].presence || Rails.root.join("tmp/repo_clones"))
      end

      # Exclusive lock so eviction or a concurrent fetch cannot remove the
      # directory under a read. This serializes tool calls per repo.
      def with_repo(environment_row:, repo:)
        dir = repo_dir(environment_row.integration.workspace_id, repo)
        FileUtils.mkdir_p(dir.dirname)

        File.open(lock_path(dir), File::RDWR | File::CREAT) do |lock|
          lock.flock(File::LOCK_EX)
          if cloned?(dir)
            fetch_if_stale!(dir, environment_row)
          else
            clone!(dir, environment_row, repo)
          end
          FileUtils.touch(used_marker(dir))
          evict_over_limit!(keep: dir)
          yield dir
        end
      end

      def show_file(dir, path)
        git!(dir, "show", "HEAD:#{path}")
      end

      # git grep exits 1 on zero matches, which is an answer, not a failure.
      def grep(dir, pattern, path_prefix = nil)
        args = [ "grep", "-nE", "--no-color", "-e", pattern, "--" ]
        args << path_prefix if path_prefix.present?
        git!(dir, *args, ok_statuses: [ 0, 1 ]).lines.map(&:chomp)
      end

      def blame(dir, path, from, to)
        porcelain = git!(dir, "blame", "-L", "#{from},#{to}", "--line-porcelain", "HEAD", "--", path)
        parse_blame(porcelain)
      end

      def remote_url(repo)
        "https://github.com/#{repo}.git"
      end

      private

      # ok_statuses admits exit codes that are answers, not failures.
      def git!(dir, *args, environment_row: nil, ok_statuses: [ 0 ])
        command = [ "git", "-c", "core.hooksPath=", "-c", "gc.auto=0" ]
        command += [ "-c", auth_header(environment_row) ] if environment_row
        command += [ "-C", dir.to_s ] if dir
        stdout, stderr, status = Open3.capture3(git_env, *command, *args.map(&:to_s))
        raise Error, "git #{args.first} failed: #{sanitize(stderr)}" unless ok_statuses.include?(status.exitstatus)

        stdout
      end

      def clone!(dir, environment_row, repo)
        git!(nil, "clone", "--quiet", remote_url(repo), dir.to_s, environment_row: environment_row)
      rescue Error
        FileUtils.rm_rf(dir)
        raise
      end

      # Freshness is the last fetch, never last use, so a hot repo keeps
      # refreshing. A fresh clone has no FETCH_HEAD, so .git's ctime stands in.
      def fetch_if_stale!(dir, environment_row)
        return if last_fetched_at(dir) > STALE_AFTER.ago

        git!(dir, "fetch", "--quiet", "origin", environment_row: environment_row)
        default = git!(dir, "symbolic-ref", "refs/remotes/origin/HEAD").strip
        git!(dir, "reset", "--hard", "--quiet", default)
      end

      def last_fetched_at(dir)
        fetch_head = dir.join(".git/FETCH_HEAD")
        fetch_head.exist? ? fetch_head.mtime : dir.join(".git").ctime
      end

      def evict_over_limit!(keep:)
        candidates = Dir.glob(root.join("*/*")).map { |path| Pathname.new(path) }
                        .select { |path| cloned?(path) && path != keep }
                        .sort_by { |path| marker_time(path) }
        overflow = candidates.size + 1 - clone_limit
        return if overflow <= 0

        candidates.first(overflow).each do |path|
          File.open(lock_path(path), File::RDWR | File::CREAT) do |lock|
            next unless lock.flock(File::LOCK_EX | File::LOCK_NB)

            FileUtils.rm_rf(path)
            FileUtils.rm_f(used_marker(path))
          end
        end
      end

      def parse_blame(porcelain)
        commits = {}
        lines = []
        current = nil
        porcelain.each_line do |raw|
          case raw
          when /\A([0-9a-f]{40}) \d+ (\d+)/
            current = { sha: Regexp.last_match(1), line: Regexp.last_match(2).to_i }
          when /\Aauthor (.+)/ then commits[current[:sha]] ||= { author: Regexp.last_match(1) }
          when /\Aauthor-time (\d+)/ then commits[current[:sha]][:date] = Time.at(Regexp.last_match(1).to_i).utc.to_date
          when /\Asummary (.+)/ then commits[current[:sha]][:summary] = Regexp.last_match(1)
          when /\A\t/
            meta = commits[current[:sha]]
            lines << BlameLine.new(line: current[:line], sha: current[:sha],
                                   author: meta[:author], date: meta[:date], summary: meta[:summary])
          end
        end
        lines
      end

      def marker_time(dir)
        marker = used_marker(dir)
        marker.exist? ? marker.mtime : Time.at(0)
      end

      def cloned?(dir)
        dir.join(".git").directory?
      end

      def repo_dir(workspace_id, repo)
        root.join(workspace_id.to_s, repo.gsub("/", "__"))
      end

      # Bookkeeping lives next to the clone, never inside it, so the working
      # tree holds only the untrusted repo's content.
      def used_marker(dir)
        Pathname.new("#{dir}.last_used")
      end

      def lock_path(dir)
        "#{dir}.lock"
      end

      def auth_header(environment_row)
        token = GithubApp.installation_token(environment_row)
        basic = Base64.strict_encode64("x-access-token:#{token}")
        "http.extraHeader=Authorization: Basic #{basic}"
      end

      def git_env
        { "GIT_TERMINAL_PROMPT" => "0", "GIT_CONFIG_NOSYSTEM" => "1", "HOME" => root.to_s }
      end

      # Strip anything header-shaped so the token never lands in an error a
      # caller might persist or show.
      def sanitize(stderr)
        stderr.to_s.gsub(/Authorization: \S+ \S+/, "Authorization: [redacted]").strip.presence || "unknown git error"
      end
    end
  end
end
