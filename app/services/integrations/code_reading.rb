module Integrations
  # A run's box. Started the first time one of its tools reads code, handed each repository with its whole history the
  # first time that repository is named, and stopped when the run ends or the box sits idle. The worker fetches with
  # the connection's token and pushes plain git objects, so no credential ever enters the box.
  class CodeReading
    NOT_SET_UP = "Code reading is not set up on this install. Whoever runs Firefight sets SANDBOX_PROVIDER to docker, northflank or boat.".freeze
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
    # A box replaced by a copy of a prepared repository is stopped this long after, so a call still reading in it ends.
    RETIRE_AFTER = 5.minutes

    class << self
      # What a prepared copy's tests cannot reach, one line each, for what could not run here. That is a service its setup
      # starts that the box cannot, with why when one from an image failed, and a Postgres extension the box's Postgres lacks.
      def not_run(prepared)
        why = prepared&.dig("left_out_why").to_h
        services = Array(prepared&.dig("left_out")).map do |name|
          why[name] ? "What needs #{name}, since it could not start in the sandbox (#{Sentence.clean(why[name])})" : "What needs #{name}, since the sandbox cannot start it"
        end
        extensions = Array(prepared&.dig("missing_extensions")).map { |missing| missing_extension(missing) }
        services + extensions
      end

      def missing_extension(missing)
        "What needs the Postgres #{missing['extension']} extension, which #{extension_named_by(missing)} names, since the sandbox's Postgres does not have it"
      end

      def extension_named_by(missing) = missing["image"].present? ? "the CI's #{missing['image']} image" : "a setup command"

      def close(key)
        box = CodeBox.live.find_by(key: key)
        stop(box) if box
      end

      # Left alone when something used it since, and that use scheduled its own check.
      def close_idle(key)
        box = CodeBox.idle.find_by(key: key)
        stop(box) if box
      end

      # Starts services in the live box a run reads code in, answering the variables that reach them. A box that is not
      # running is not started for this, since nothing in it would use them.
      def start_services(key, names)
        box = CodeBox.live.find_by(key: key)
        raise Error, "The sandbox for this change is not running, so nothing was started." unless box

        box.used!
        Sandboxes::Client.new(box_of(box)).start_services(names)
      end

      def stop(box)
        return unless box.stop!

        Sandboxes.provider(box.provider)&.stop(box.box_ref)
      rescue Sandboxes::Error => error
        Rails.logger.warn({ event: "code_box.stop_failed", code_box_id: box.id, error: error.message }.to_json)
      end

      # Stops a box no row names any more, after a row moved to another box.
      def retire(provider_key, ref)
        Sandboxes.provider(provider_key)&.stop(ref)
      rescue Sandboxes::Error => error
        Rails.logger.warn({ event: "code_box.stop_failed", provider: provider_key, box_ref: ref, error: error.message }.to_json)
      end

      # Boxes nothing has used for a while, boxes a provider still runs that no row knows, and what a provider keeps that
      # the app no longer needs, then what each provider holds now. One provider that cannot be asked leaves the others.
      def sweep!
        CodeBox.abandoned.find_each { |box| stop(box) }
        known = CodeBox.live.pluck(:box_ref).to_set
        SandboxProviders.in_use.each do |key|
          provider = Sandboxes.provider(key)
          provider.running.each do |running|
            next if known.include?(running.ref) || running.started_at.nil? || running.started_at > ORPHAN_GRACE.ago

            provider.stop(running.ref)
          end
          provider.tidy(kept_refs: PreparedCopy.where(kept_in: key).pluck(:kept_ref).to_set)
        rescue Sandboxes::Error => error
          Rails.logger.warn({ event: "code_box.sweep_failed", provider: key, error: error.message }.to_json)
        end
        SandboxInventory.record!
      end

      # Prepared copies nobody used for PreparedCopy::KEPT_UNUSED_FOR. A copy a provider keeps is let go of there first,
      # and kept here when the provider cannot be asked, so the next sweep tries again.
      def sweep_prepared!
        PreparedCopy.unused.kept_by_providers.find_each do |kept|
          Sandboxes.provider(kept.kept_in).discard(kept.kept_ref)
          kept.destroy
        rescue Sandboxes::Error => error
          Rails.logger.warn({ event: "prepared_copy.discard_failed", prepared_copy_id: kept.id, error: error.message }.to_json)
        end
        PreparedCopy.sweep!
      end

      # How the client reaches the box a row names.
      def box_of(row)
        Sandboxes::Box.new(ref: row.box_ref, address: row.reach_address, key: row.secret, relayed: Sandboxes.provider(row.provider)&.relayed? || false)
      end

      # In process memory, since one run's reads happen in the job that holds it. An entry past its time is dropped
      # when it is next read or another is added, so a long-lived worker does not keep one per run.
      def unavailable(key)
        failed = unavailable_by_key[key]
        return unless failed
        return failed[:message] if failed[:at] > UNAVAILABLE_FOR.ago

        unavailable_by_key.delete_pair(key, failed)
        nil
      end

      def unavailable!(key, message)
        unavailable_by_key.each_pair { |stale, entry| unavailable_by_key.delete_pair(stale, entry) if entry[:at] <= UNAVAILABLE_FOR.ago }
        unavailable_by_key[key] = { message: message, at: Time.current }
        message
      end

      private

      def unavailable_by_key = @unavailable_by_key ||= Concurrent::Map.new
    end

    # Where git fetches a repository from and who it signs in as. The code host's pack gives it, with token read only
    # when a fetch needs one, so this class knows no code host. host names a code host other than the default one, so
    # the same path on two hosts is two repositories in the box. options are git settings the fetch adds, such as the
    # address a workspace's own host was checked at.
    Remote = Data.define(:root, :user, :token, :host, :options) do
      def initialize(host: nil, options: [], **) = super

      def url(repository) = "#{root}/#{repository}.git"

      # The repository as the box records it.
      def key(repository) = host ? "#{host}:#{repository}" : repository.to_s

      # The sandbox takes owner__name. A host's path can hold groups and dots, so its own name gets a digest to stay one.
      def stored_name(repository)
        return repository.to_s.sub("/", "__") unless host

        "#{host}__#{repository.to_s.tr('/', '.')}-#{Digest::SHA256.hexdigest(repository.to_s)[0, 10]}"
      end
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

    # Installs what the copy at ref needs and runs the repository's setup (RepositorySetup#for_box) in it. A copy whose
    # lockfiles, version files and setup match one this workspace prepared before starts with what that one installed
    # (PreparedCopy), and one installed from nothing is kept for the next. A box from an image before setups prepares
    # as it always did.
    #
    # Where the box's provider keeps a box's disk itself, the copy is kept there instead (Sandboxes::Provider#keep), and
    # a box holding nothing but this repository is replaced by one started from the kept copy, which then hands what it
    # installed to the copy at ref.
    def prepare(repository, ref: nil, setup: nil)
      with_repository(repository) do |name|
        next client.prepare(repository: name, ref: ref) unless client.setups?

        state = client.prepare_state(repository: name, ref: ref)
        key = PreparedCopy.key_for(lock_digest: state["lock_digest"], setup_digest: setup && Digest::SHA256.hexdigest(JSON.generate(setup)))
        keeper = box_provider&.keeps_copies? ? box_provider : nil
        unless state["prepared"]
          keeper ? start_from_kept(keeper, repository, name, ref, key) : restore_prepared(repository, name, ref, key)
        end
        prepared = client.prepare(repository: name, ref: ref, setup: setup)
        if prepared_from_nothing?(prepared)
          keeper ? keep_in_provider(keeper, repository, key, prepared["commit"]) : keep_prepared(repository, name, ref, key)
        end
        prepared
      end
    end

    def lsp(repository, **options)
      with_repository(repository) { |name| client.lsp(repository: name, **options) }
    end

    private

    def box_provider = Sandboxes.provider(box.provider)

    # Moves the run to a box started from what this workspace kept for the repository and key, when the box holds no
    # other repository, so nothing the run already pushed is lost. The box it leaves is stopped once calls still reading
    # in it are done. Anything that goes wrong before the move leaves the box as it was, to install from nothing.
    def start_from_kept(keeper, repository, name, ref, key)
      return unless box.repositories.keys == [ @remote.key(repository) ]

      kept = PreparedCopy.kept_by(box.provider, @workspace, @remote.key(repository), key)
      return unless kept&.commit.present? && keeper.kept_ready?(kept.kept_ref)

      started = keeper.start(name: Sandboxes.box_name, from: kept.kept_ref)
      Sandboxes::Client.new(started).wait_until_ready!
      left = box.box_ref
      return keeper.stop(started.ref) unless box.moved_to!(started, hourly_micros: keeper.hourly_micros)

      started = nil
      @client = nil
      CodeBoxRetireJob.set(wait: RETIRE_AFTER).perform_later(box.provider, left)
      kept.used!
      push!(repository)
      client.seed(repository: name, ref: ref, from: kept.commit)
    rescue Sandboxes::Error => error
      keeper.stop(started.ref) if started
      Rails.logger.warn({ event: "prepared_copy.start_failed", prepared_copy_id: kept&.id, error: error.message }.to_json)
    end

    # Asks the provider to keep the box's disk as it is now, with the copy just prepared, and drops this repository's
    # oldest copies past PreparedCopy::KEPT_PER_REPOSITORY. A copy that cannot be kept is simply not kept.
    def keep_in_provider(keeper, repository, key, commit)
      return if PreparedCopy.kept_by(box.provider, @workspace, @remote.key(repository), key)

      name = keeper.keep(box.box_ref)
      kept, dropped = PreparedCopy.kept!(box.provider, @workspace, @remote.key(repository), key, kept_ref: name, commit: commit)
      return keeper.discard(name) unless kept

      dropped.each do |old|
        keeper.discard(old.kept_ref)
        old.destroy
      end
    rescue Sandboxes::Error => error
      Rails.logger.warn({ event: "prepared_copy.keep_failed", repository: @remote.key(repository), error: error.message }.to_json)
    end

    def prepared_from_nothing?(prepared)
      !prepared["already"] && !prepared["restored"] && (Array(prepared["prepared"]) + Array(prepared["setup"])).all? { |step| step["exit_code"].to_i.zero? }
    end

    # What a copy this workspace prepared before installed, handed to the box. Anything that goes wrong leaves the copy
    # to install from nothing.
    def restore_prepared(repository, name, ref, key)
      kept = PreparedCopy.usable(@workspace, @remote.key(repository), key)
      return unless kept

      kept.archive.open { |file| client.upload_archive(repository: name, ref: ref, path: file.path) }
      kept.used!
    rescue Sandboxes::Error, ActiveStorage::Error, SystemCallError => error
      Rails.logger.warn({ event: "prepared_copy.restore_failed", prepared_copy_id: kept&.id, error: error.message }.to_json)
    end

    # What the copy installed, kept for the next copy with the same key. A copy too large to keep, or one the box could
    # not pack, is simply not kept.
    def keep_prepared(repository, name, ref, key)
      Dir.mktmpdir("prepared-copy") do |dir|
        path = File.join(dir, "prepared.tar.gz")
        client.download_archive(repository: name, ref: ref, path: path, limit: PreparedCopy::MAX_BYTES)
        PreparedCopy.keep!(@workspace, @remote.key(repository), key, path)
      end
    rescue Sandboxes::Error, ActiveStorage::Error, SystemCallError => error
      Rails.logger.warn({ event: "prepared_copy.keep_failed", repository: @remote.key(repository), error: error.message }.to_json)
    end

    # A box can be gone while its row says it is live, stopped by hand, by a restart or by the provider. When a call
    # fails and the box no longer answers, its row is closed and the call runs once more in a new box.
    def with_repository(repository, replaced: false, &)
      ensure_repository!(repository)
      box.used!
      yield @remote.stored_name(repository)
    rescue Sandboxes::Error => error
      if error.message.match?(MISSING_COMMIT) && refetchable?(repository)
        push!(repository)
        return yield @remote.stored_name(repository)
      end
      raise if replaced || client.alive?

      replace_lost_box!
      with_repository(repository, replaced: true, &)
    end

    # A row that moved to another box meanwhile, from a kept copy, is followed there rather than stopped.
    def replace_lost_box!
      current = CodeBox.live.find_by(id: box.id)
      if current && current.box_ref != box.box_ref
        @box = current
      else
        self.class.stop(box)
        @box = nil
      end
      @client = nil
    end

    def refetchable?(repository)
      pushed = box.reload.repositories.dig(@remote.key(repository), "pushed_at")
      pushed.nil? || Time.zone.parse(pushed) < REFETCH_AFTER.ago
    end

    def client = @client ||= Sandboxes::Client.new(self.class.box_of(box))

    # One box per key. Two tools a model calls at once take turns here rather than starting two.
    def box
      @box ||= locked(@key) { CodeBox.live.find_by(key: @key) || start! }
    end

    # Tries the workspace's providers in order (SandboxProviders.order_for). A provider that cannot start a box, from
    # capacity, an outage, a timeout or a refusal, hands over to the next, and the box remembers which one refused it
    # first and why, for the operator console.
    def start!
      known = self.class.unavailable(@key)
      raise Unavailable, known if known

      keys = SandboxProviders.order_for(@workspace)
      raise Unavailable, self.class.unavailable!(@key, format(UNAVAILABLE, reason: NOT_SET_UP)) if keys.empty?

      refused = []
      keys.each_with_index do |provider_key, index|
        row = start_on(provider_key, fail_fast: index < keys.size - 1, refused: refused.first)
        return row if row
      rescue Sandboxes::Error => error
        refused << [ provider_key, error.message ]
      end
      reason = refused.map { |provider_key, message| keys.size > 1 ? "#{SandboxProviders.name_of(provider_key)}: #{message}" : message }.join(" ")
      raise Unavailable, self.class.unavailable!(@key, format(UNAVAILABLE, reason: reason))
    end

    def start_on(provider_key, fail_fast:, refused:)
      provider = Sandboxes.provider(provider_key)
      started = provider.start(name: Sandboxes.box_name, fail_fast: fail_fast)
      Sandboxes::Client.new(started).wait_until_ready!
      CodeBox.create!(
        workspace: @workspace, key: @key, provider: provider_key, box_ref: started.ref, **CodeBox.address_columns(started.address), secret: started.key,
        last_used_at: Time.current, box_started_at: Time.current, size: provider.size, hourly_micros: provider.hourly_micros,
        failed_over_from: refused&.first, failover_reason: refused&.last
      )
    rescue StandardError
      provider.stop(started.ref) if started
      raise
    end

    def ensure_repository!(repository)
      return if box.holds?(@remote.key(repository))

      locked("#{@key}:#{@remote.key(repository)}") { push!(repository) unless box.reload.holds?(@remote.key(repository)) }
    end

    def push!(repository)
      pushed = Dir.mktmpdir("code-box") do |dir|
        mirror = File.join(dir, "mirror.git")
        bundle = File.join(dir, "repository.bundle")
        git!(dir, "clone", "--mirror", "--quiet", remote_url(repository), mirror, authenticated: true)
        git!(dir, "--git-dir", mirror, "bundle", "create", "--quiet", bundle, "--all")
        client.push(@remote.stored_name(repository), File.binread(bundle))
      end
      box.record_repository!(@remote.key(repository), head: pushed["head"], default_branch: pushed["default_branch"])
    end

    def remote_url(repository) = @remote.url(repository)

    def git!(dir, *arguments, authenticated: false)
      prefix = authenticated ? [ "-c", "http.extraHeader=Authorization: Basic #{credential}", *@remote.options.flat_map { |option| [ "-c", option ] } ] : []
      env = { "GIT_TERMINAL_PROMPT" => "0", "GIT_CONFIG_NOSYSTEM" => "1", "HOME" => dir }
      _output, errors, status = Open3.capture3(env, "git", *prefix, *arguments)
      raise Error, "git #{arguments.first} failed: #{redacted(errors).strip.lines.last}" unless status.success?
    end

    def credential
      @credential ||= Base64.strict_encode64("#{@remote.user}:#{token}")
    end

    def token = @token ||= @remote.token.call

    # git's own words with the credential and the token taken out, both as given and encoded.
    def redacted(text) = @credential ? text.gsub(@credential, "[redacted]").gsub(token, "[redacted]") : text

    # Held for the length of one transaction, so a second worker waits and then finds what the first one made.
    def locked(name)
      CodeBox.transaction do
        CodeBox.connection.execute(CodeBox.sanitize_sql([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", "code_box:#{name}" ]))
        yield
      end
    end
  end
end
