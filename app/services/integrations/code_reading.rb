module Integrations
  # A run's box. Started the first time one of its tools reads code, handed each repository with its whole history the
  # first time that repository is named, and stopped when the run ends or the box sits idle. The worker fetches with
  # the connection's token and pushes plain git objects, so no credential ever enters the box.
  class CodeReading
    NOT_SET_UP = "Code reading is not set up on this install. Whoever runs Firefight sets SANDBOX_PROVIDER to docker or northflank.".freeze
    # What the agent is told when the box cannot start, so it stops reaching for code tools and says why in its answer.
    UNAVAILABLE = "Code reading cannot run right now: %<reason>s Every tool that reads code in the sandbox will fail the " \
                  "same way for the rest of this run, whatever you pass, so do not call them again. Fetching one file " \
                  "or its blame from the code host still works. Say in your answer that code could not be searched, " \
                  "and why.".freeze
    # A box that would not start is not tried again for this long, so a run's later reads fail at once.
    UNAVAILABLE_FOR = 10.minutes
    MISSING_COMMIT = /has no commit/
    # A commit the box does not know may have been pushed since, so the repository is fetched again once.
    REFETCH_AFTER = 30.seconds
    # A box a provider started this recently may still be on its way into the table, so the sweep leaves it alone.
    ORPHAN_GRACE = 15.minutes

    class << self
      def close(key)
        box = CodeBox.live.find_by(key: key)
        stop(box) if box
      end

      # Left alone when something used it since, and that use scheduled its own check.
      def close_idle(key)
        box = CodeBox.idle.find_by(key: key)
        stop(box) if box
      end

      def stop(box)
        return unless box.stop!

        provider_for(box.provider)&.stop(box.box_ref)
      rescue Sandboxes::Error => error
        Rails.logger.warn({ event: "code_box.stop_failed", code_box_id: box.id, error: error.message }.to_json)
      end

      # Boxes nothing has used for a while, and boxes a provider still runs that no row knows.
      def sweep!
        CodeBox.abandoned.find_each { |box| stop(box) }
        provider = Sandboxes.provider
        return unless provider

        known = CodeBox.live.pluck(:box_ref).to_set
        provider.running.each do |running|
          next if known.include?(running.ref) || running.started_at.nil? || running.started_at > ORPHAN_GRACE.ago

          provider.stop(running.ref)
        end
      end

      # In process memory, since one run's reads happen in the job that holds it.
      def unavailable(key)
        failed = unavailable_by_key[key]
        failed[:message] if failed && failed[:at] > UNAVAILABLE_FOR.ago
      end

      def unavailable!(key, message)
        unavailable_by_key[key] = { message: message, at: Time.current }
        message
      end

      private

      def unavailable_by_key = @unavailable_by_key ||= Concurrent::Map.new

      def provider_for(key) = key == Sandboxes.provider_key ? Sandboxes.provider : nil
    end

    # Where git fetches a repository from and who it signs in as. The code host's pack gives it, with token read only
    # when a fetch needs one, so this class knows no code host.
    Remote = Data.define(:root, :user, :token) do
      def url(repository) = "#{root}/#{repository}.git"
    end

    def initialize(key:, workspace:, remote:)
      raise Error, "A code tool was called outside a run, so there is no box to read in." if key.blank?

      @key = key
      @workspace = workspace
      @remote = remote
    end

    def exec(repository, **options)
      with_repository(repository) { |name| client.exec(repository: name, **options) }
    end

    def prepare(repository, ref: nil)
      with_repository(repository) { |name| client.prepare(repository: name, ref: ref) }
    end

    def lsp(repository, **options)
      with_repository(repository) { |name| client.lsp(repository: name, **options) }
    end

    private

    # A box can be gone while its row says it is live, stopped by hand, by a restart or by the provider. When a call
    # fails and the box no longer answers, its row is closed and the call runs once more in a new box.
    def with_repository(repository, replaced: false, &)
      ensure_repository!(repository)
      box.used!
      yield stored_name(repository)
    rescue Sandboxes::Error => error
      if error.message.match?(MISSING_COMMIT) && refetchable?(repository)
        push!(repository)
        return yield stored_name(repository)
      end
      raise if replaced || client.alive?

      replace_lost_box!
      with_repository(repository, replaced: true, &)
    end

    def replace_lost_box!
      self.class.stop(box)
      @box = nil
      @client = nil
    end

    def refetchable?(repository)
      pushed = box.reload.repositories.dig(repository, "pushed_at")
      pushed.nil? || Time.zone.parse(pushed) < REFETCH_AFTER.ago
    end

    def client = @client ||= Sandboxes::Client.new(Sandboxes::Box.new(ref: box.box_ref, address: box.address, key: box.secret))

    # One box per key. Two tools a model calls at once take turns here rather than starting two.
    def box
      @box ||= locked(@key) { CodeBox.live.find_by(key: @key) || start! }
    end

    def start!
      known = self.class.unavailable(@key)
      raise Unavailable, known if known

      provider = Sandboxes.provider
      raise Unavailable, self.class.unavailable!(@key, format(UNAVAILABLE, reason: NOT_SET_UP)) unless provider

      started = provider.start(name: Sandboxes.box_name)
      Sandboxes::Client.new(started).wait_until_ready!
      CodeBox.create!(
        workspace: @workspace, key: @key, provider: Sandboxes.provider_key, box_ref: started.ref,
        address: started.address, secret: started.key, last_used_at: Time.current
      )
    rescue Sandboxes::Error => error
      provider&.stop(started.ref) if started
      raise Unavailable, self.class.unavailable!(@key, format(UNAVAILABLE, reason: error.message))
    rescue StandardError
      provider&.stop(started.ref) if started
      raise
    end

    def ensure_repository!(repository)
      return if box.holds?(repository)

      locked("#{@key}:#{repository}") { push!(repository) unless box.reload.holds?(repository) }
    end

    def push!(repository)
      pushed = Dir.mktmpdir("code-box") do |dir|
        mirror = File.join(dir, "mirror.git")
        bundle = File.join(dir, "repository.bundle")
        git!(dir, "clone", "--mirror", "--quiet", remote_url(repository), mirror, authenticated: true)
        git!(dir, "--git-dir", mirror, "bundle", "create", "--quiet", bundle, "--all")
        client.push(stored_name(repository), File.binread(bundle))
      end
      box.record_repository!(repository, head: pushed["head"], default_branch: pushed["default_branch"])
    end

    def remote_url(repository) = @remote.url(repository)

    def stored_name(repository) = repository.to_s.sub("/", "__")

    def git!(dir, *arguments, authenticated: false)
      prefix = authenticated ? [ "-c", "http.extraHeader=Authorization: Basic #{credential}" ] : []
      env = { "GIT_TERMINAL_PROMPT" => "0", "GIT_CONFIG_NOSYSTEM" => "1", "HOME" => dir }
      _output, errors, status = Open3.capture3(env, "git", *prefix, *arguments)
      raise Error, "git #{arguments.first} failed: #{errors.gsub(credential, '[redacted]').strip.lines.last}" unless status.success?
    end

    def credential
      @credential ||= Base64.strict_encode64("#{@remote.user}:#{@remote.token.call}")
    end

    # Held for the length of one transaction, so a second worker waits and then finds what the first one made.
    def locked(name)
      CodeBox.transaction do
        CodeBox.connection.execute(CodeBox.sanitize_sql([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", "code_box:#{name}" ]))
        yield
      end
    end
  end
end
