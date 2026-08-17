require "open3"

module Integrations
  # Warm local clones of customer repositories for the code tools. Clones on
  # first use, fetches when stale, and evicts least-recently-used repos over
  # the cap. Repo content is untrusted input: git runs with hooks disabled
  # and prompts off, arguments are exec'd as arrays (never a shell), tools
  # read content only through git object commands (git show/grep/blame), and
  # the installation token rides a per-invocation header so it is never
  # written into the clone's config.
  class CloneManager
    class Error < Integrations::Error; end

    STALE_AFTER = 5.minutes
    USED_MARKER = ".ff_last_used".freeze

    class << self
      def clone_limit
        (ENV["REPO_CLONE_LIMIT"].presence || 20).to_i
      end

      def root
        Pathname.new(ENV["REPO_CLONE_ROOT"].presence || Rails.root.join("tmp/repo_clones"))
      end

      # Yields the clone's path with an exclusive lock held, so eviction or a
      # concurrent fetch can never rip the directory out from under a read.
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
          FileUtils.touch(dir.join(USED_MARKER))
          evict_over_limit!(keep: dir)
          yield dir
        end
      end

      def remote_url(repo)
        "https://github.com/#{repo}.git"
      end

      # git with the safety rails on: no hooks, no prompts, no system config,
      # arguments exec'd directly. Auth is a per-invocation header, never
      # persisted state. ok_statuses admits exit codes that are answers, not
      # failures (git grep exits 1 for zero matches).
      def git!(dir, *args, environment_row: nil, ok_statuses: [ 0 ])
        command = [ "git", "-c", "core.hooksPath=", "-c", "gc.auto=0" ]
        command += [ "-c", auth_header(environment_row) ] if environment_row
        command += [ "-C", dir.to_s ] if dir
        stdout, stderr, status = Open3.capture3(git_env, *command, *args.map(&:to_s))
        raise Error, "git #{args.first} failed: #{sanitize(stderr)}" unless ok_statuses.include?(status.exitstatus)

        stdout
      end

      private

      def clone!(dir, environment_row, repo)
        git!(nil, "clone", "--quiet", remote_url(repo), dir.to_s, environment_row: environment_row)
      rescue Error
        FileUtils.rm_rf(dir)
        raise
      end

      def fetch_if_stale!(dir, environment_row)
        marker = dir.join(USED_MARKER)
        return if marker.exist? && marker.mtime > STALE_AFTER.ago

        git!(dir, "fetch", "--quiet", "origin", environment_row: environment_row)
        default = git!(dir, "symbolic-ref", "refs/remotes/origin/HEAD").strip
        git!(dir, "reset", "--hard", "--quiet", default)
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
          end
        end
      end

      def marker_time(dir)
        marker = dir.join(USED_MARKER)
        marker.exist? ? marker.mtime : Time.at(0)
      end

      def cloned?(dir)
        dir.join(".git").directory?
      end

      def repo_dir(workspace_id, repo)
        root.join(workspace_id.to_s, repo.gsub("/", "__"))
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

      # Auth values must never surface in an error a caller might persist or
      # show; strip anything header-shaped from git's stderr.
      def sanitize(stderr)
        stderr.to_s.gsub(/Authorization: \S+ \S+/, "Authorization: [redacted]").strip.presence || "unknown git error"
      end
    end
  end
end
