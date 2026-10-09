# The command service inside a sandbox. The app pushes repositories in and asks for commands by argument list,
# never by a string the box would have to trust. Standard library only, so the image carries nothing to keep patched.
require "socket"
require "json"
require "open3"
require "fileutils"
require "tmpdir"
require "securerandom"
require "digest"
require "uri"

module Sandbox
  KEY = ENV.fetch("SANDBOX_KEY")
  PORT = Integer(ENV.fetch("PORT", "8080"))
  CODE = "/code"
  WORK = "/work"
  RUNS = "/runs"
  # What a command started in the background writes as it goes, one file per command, read back by offset.
  PROGRESS = ENV.fetch("SANDBOX_PROGRESS_DIR", "/progress")
  OUTPUT_LIMIT = 10 * 1024 * 1024
  DEFAULT_TIMEOUT = 60
  MAX_TIMEOUT = 20 * 60
  USERS = %w[reader runner].freeze
  REPO_NAME = /\A[\w.\-]+__[\w.\-]+\z/
  LOCKS = Hash.new { |hash, key| hash[key] = Mutex.new }
  LOCKS_GUARD = Mutex.new

  # The image's own settings every command needs, such as where the base image keeps its gems. Nothing else is passed on.
  INHERITED = %w[PATH GEM_HOME BUNDLE_APP_CONFIG BUNDLE_SILENCE_ROOT_WARNING MISE_DATA_DIR MISE_CONFIG_DIR MISE_CACHE_DIR].freeze

  class Refused < StandardError; end

  def self.base_env(home) = ENV.to_h.slice(*INHERITED).merge("HOME" => home, "LANG" => "C.UTF-8", "GIT_TERMINAL_PROMPT" => "0")

  def self.given(value) = value.to_s.strip.empty? ? nil : value.to_s.strip

  def self.lock(key, &)
    mutex = LOCKS_GUARD.synchronize { LOCKS[key] }
    mutex.synchronize(&)
  end

  # Runs argv with no shell, as the given user when one is named, and gives up after timeout seconds.
  def self.run(argv, dir: "/", user: nil, timeout: DEFAULT_TIMEOUT, env: {}, stdin: nil)
    command = user ? [ "setpriv", "--reuid=#{user}", "--regid=#{user}", "--init-groups", "--", *argv ] : argv
    base = base_env(user ? "/home/#{user}" : "/root")
    out = +""
    err = +""
    truncated = false
    timed_out = false
    status = nil
    Open3.popen3(base.merge(env), *command, chdir: dir, pgroup: true, unsetenv_others: true) do |input, stdout, stderr, waiter|
      input.write(stdin) if stdin
      input.close
      readers = [ [ stdout, out ], [ stderr, err ] ].map do |stream, buffer|
        Thread.new do
          while (chunk = stream.readpartial(64 * 1024) rescue nil)
            if buffer.bytesize + chunk.bytesize > OUTPUT_LIMIT
              buffer << chunk.byteslice(0, OUTPUT_LIMIT - buffer.bytesize)
              truncated = true
            else
              buffer << chunk
            end
          end
        end
      end
      unless waiter.join(timeout)
        timed_out = true
        Process.kill("KILL", -waiter.pid) rescue nil
      end
      status = waiter.value
      readers.each { |reader| reader.join(5) }
    end
    {
      "stdout" => out.force_encoding(Encoding::UTF_8).scrub, "stderr" => err.force_encoding(Encoding::UTF_8).scrub,
      "exit_code" => status&.exitstatus, "timed_out" => timed_out, "truncated" => truncated
    }
  end

  def self.run!(argv, **options)
    result = run(argv, **options)
    raise Refused, "#{argv.first} failed: #{result['stderr'].strip.lines.last(3).join}" unless result["exit_code"] == 0

    result["stdout"]
  end

  module Repos
    def self.bare(name)
      raise Refused, "Not a repository name: #{name}" unless name.to_s.match?(REPO_NAME)

      File.join(CODE, "#{name}.git")
    end

    # A second push of the same repository fetches into it, so a box keeps one copy with every commit it was sent.
    def self.push(name, bundle)
      path = bare(name)
      Sandbox.lock("repo:#{name}") do
        Dir.mktmpdir do |tmp|
          file = File.join(tmp, "repo.bundle")
          File.binwrite(file, bundle)
          if File.directory?(path)
            Sandbox.run!([ "git", "--git-dir", path, "fetch", "--quiet", "--force", file, "+refs/*:refs/*" ])
          else
            Sandbox.run!([ "git", "clone", "--quiet", "--bare", file, path ])
          end
        end
        head = Sandbox.run!([ "git", "--git-dir", path, "rev-parse", "HEAD" ]).strip
        branch = Sandbox.run!([ "git", "--git-dir", path, "symbolic-ref", "--short", "HEAD" ]).strip
        { "head" => head, "default_branch" => branch }
      end
    end

    def self.commit(name, ref)
      wanted = ref.to_s.strip.empty? ? "HEAD" : ref.to_s
      raise Refused, "Not a ref: #{wanted}" if wanted.start_with?("-")

      result = Sandbox.run([ "git", "--git-dir", bare(name), "rev-parse", "--verify", "--quiet", "#{wanted}^{commit}" ])
      raise Refused, "#{name} has no commit #{wanted}" unless result["exit_code"] == 0

      result["stdout"].strip
    end

    # A read-only checkout per commit, shared by every read at that commit.
    def self.checkout(name, sha)
      dir = File.join(WORK, name, sha)
      Sandbox.lock("checkout:#{dir}") do
        unless File.directory?(dir)
          FileUtils.mkdir_p(File.dirname(dir))
          Sandbox.run!([ "git", "--git-dir", bare(name), "worktree", "add", "--quiet", "--detach", dir, sha ])
        end
      end
      dir
    end

    # A writable copy for runner, kept for the life of the box so dependencies install once.
    def self.run_copy(name, sha)
      dir = File.join(RUNS, "#{name}-#{sha}")
      Sandbox.lock("run:#{dir}") do
        unless File.directory?(dir)
          Sandbox.run!([ "git", "clone", "--quiet", "--no-checkout", bare(name), dir ], user: "runner")
          Sandbox.run!([ "git", "checkout", "--quiet", "--detach", sha ], dir: dir, user: "runner")
        end
      end
      dir
    end
  end

  # Postgres and Redis inside the box, one of each, on the port a repository's CI gave them or their usual one. A
  # repository's setup names them with the settings its CI started them with, and the app's tools by name.
  module Services
    STARTED = {}
    KNOWN = %w[postgres redis].freeze
    DEFAULT_PORTS = { "postgres" => 5432, "redis" => 6379 }.freeze
    # A role or database a setup asks for, which goes into SQL inside double quotes.
    IDENTIFIER = /\A[A-Za-z_][\w-]{0,62}\z/
    # The extension a Postgres image is built around, by the image's own name, which its CI's tests expect to find.
    IMAGE_EXTENSIONS = { "pgvector" => "vector", "postgis" => "postgis", "timescaledb" => "timescaledb", "timescaledb-ha" => "timescaledb",
                         "citus" => "citus", "paradedb" => "pg_search", "pgrouting" => "pgrouting" }.freeze
    CREATE_EXTENSION = /\bCREATE\s+EXTENSION\s+(?:IF\s+NOT\s+EXISTS\s+)?"?([A-Za-z_][\w-]*)"?/i

    # names is a list of service names, or of { "name", "port", "env" } as a setup gives them. Any other name is refused.
    def self.start(names)
      Array(names).each_with_object({}) do |service, env|
        name, port, settings = parts(service)
        raise Refused, "No service called #{name}. There are postgres and redis." unless KNOWN.include?(name)

        env.merge!(start_one(name, port, settings))
      end
    end

    # A setup's services, leaving out the ones the box cannot start rather than failing, and saying which those were.
    def self.start_known(services)
      known, unknown = Array(services).partition { |service| KNOWN.include?(parts(service).first) }
      [ start(known), unknown.map { |service| parts(service).first } ]
    end

    # The Postgres extensions a setup names, by its postgres service's image or a setup command that creates one, that the
    # box's Postgres does not have, each with the image that named it. Nothing when the setup starts no Postgres.
    def self.missing_extensions(setup)
      postgres = Array((setup || {})["services"]).select { |service| parts(service).first == "postgres" }
      port = STARTED["postgres"]
      return [] if postgres.empty? || !port

      named = postgres.filter_map do |service|
        image = Sandbox.given(service["image"]) if service.is_a?(Hash)
        extension = IMAGE_EXTENSIONS[image.split("@").first.split("/").last.split(":").first.downcase] if image
        { "extension" => extension, "image" => image } if extension
      end
      Array(setup["commands"]).each { |command| command.to_s.scan(CREATE_EXTENSION) { |(extension)| named << { "extension" => extension.downcase } } }
      listed = Sandbox.run([ "psql", "-h", "127.0.0.1", "-p", port.to_s, "-U", "runner", "-d", "postgres", "-qAt", "-c", "SELECT name FROM pg_available_extensions" ], user: "runner")
      return [] unless listed["exit_code"] == 0

      available = listed["stdout"].split("\n").map(&:strip)
      named.uniq { |entry| entry["extension"] }.reject { |entry| available.include?(entry["extension"]) }
    end

    def self.parts(service)
      return [ service.to_s, nil, nil ] unless service.is_a?(Hash)

      [ service["name"].to_s, service["port"] && Integer(service["port"]), service["env"] ]
    end

    def self.start_one(name, port, settings)
      port ||= DEFAULT_PORTS.fetch(name)
      raise Refused, "#{name} cannot listen on port #{port}." unless port.between?(1024, 65_535)

      name == "postgres" ? postgres(port, settings) : redis(port)
    end

    def self.running_on!(name, port)
      started = STARTED[name]
      raise Refused, "#{name} is already running on port #{started}, so it cannot start again on #{port}." if started && started != port

      started
    end

    def self.postgres(port, settings)
      Sandbox.lock("service:postgres") do
        unless running_on!("postgres", port)
          data = "/var/lib/postgresql/sandbox"
          bin = Dir["/usr/lib/postgresql/*/bin"].max
          unless File.directory?(data)
            FileUtils.mkdir_p(data)
            FileUtils.chown("postgres", "postgres", data)
            Sandbox.run!([ "#{bin}/initdb", "-D", data, "-A", "trust", "-U", "runner" ], user: "postgres")
          end
          Sandbox.run!([ "#{bin}/pg_ctl", "-D", data, "-l", "/tmp/postgres.log", "-o", "-k /tmp -p #{port} -c listen_addresses=127.0.0.1", "-w", "start" ], user: "postgres")
          STARTED["postgres"] = port
        end
        return { "DATABASE_URL" => "postgres://runner@127.0.0.1:#{port}/postgres", "PGHOST" => "127.0.0.1", "PGPORT" => port.to_s, "PGUSER" => "runner" } unless settings

        # As the official image does, the role and database a CI job named, postgres when it named none. Any password
        # signs in, since the box's Postgres trusts every local connection.
        user = Sandbox.given(settings["POSTGRES_USER"]) || "postgres"
        database = Sandbox.given(settings["POSTGRES_DB"]) || user
        [ user, database ].each { |identifier| raise Refused, "#{identifier} is not a name Postgres takes here." unless identifier.match?(IDENTIFIER) }
        sql = "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{user}') THEN CREATE ROLE \"#{user}\" LOGIN SUPERUSER; END IF; END $$;"
        psql = [ "psql", "-h", "127.0.0.1", "-p", port.to_s, "-U", "runner", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qAt", "-c" ]
        Sandbox.run!([ *psql, sql ], user: "runner")
        exists = Sandbox.run!([ *psql, "SELECT 1 FROM pg_database WHERE datname = '#{database}'" ], user: "runner").strip == "1"
        Sandbox.run!([ *psql, "CREATE DATABASE \"#{database}\" OWNER \"#{user}\"" ], user: "runner") unless exists
        { "DATABASE_URL" => "postgres://#{user}@127.0.0.1:#{port}/#{database}", "PGHOST" => "127.0.0.1", "PGPORT" => port.to_s, "PGUSER" => user,
          "PGDATABASE" => database }
      end
    end

    def self.redis(port)
      Sandbox.lock("service:redis") do
        unless running_on!("redis", port)
          Sandbox.run!([ "redis-server", "--daemonize", "yes", "--bind", "127.0.0.1", "--port", port.to_s, "--save", "", "--appendonly", "no" ], user: "runner")
          STARTED["redis"] = port
        end
      end
      { "REDIS_URL" => "redis://127.0.0.1:#{port}/0" }
    end
  end

  # Installs what a repository's lockfiles and version files ask for, once per copy, then sets it up as its CI does: the
  # services, the environment and the commands the repository's setup names. A copy restored from what an earlier one
  # installed only runs each installer again, which finds everything there, before the setup's commands.
  module Prepare
    STEPS = [
      [ ".tool-versions", [ "mise", "install", "--yes" ] ],
      [ "mise.toml", [ "mise", "install", "--yes" ] ],
      [ ".ruby-version", [ "mise", "install", "--yes" ] ],
      [ ".nvmrc", [ "mise", "install", "--yes" ] ],
      [ "Gemfile.lock", [ "sh", "-c", "bundle config set --local path vendor/bundle && bundle install --jobs 4" ] ],
      [ "package-lock.json", [ "npm", "ci", "--no-fund", "--no-audit" ] ],
      [ "yarn.lock", [ "sh", "-c", "corepack enable --install-directory ~/.local/bin && yarn install --frozen-lockfile" ] ],
      [ "pnpm-lock.yaml", [ "sh", "-c", "corepack enable --install-directory ~/.local/bin && pnpm install --frozen-lockfile" ] ],
      [ "requirements.txt", [ "sh", "-c", "python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" ] ],
      [ "go.mod", [ "go", "mod", "download" ] ]
    ].freeze
    # npm ci starts from nothing, so a restored copy asks npm install instead, which leaves what matches the lockfile.
    REFRESH = STEPS.map { |file, argv| file == "package-lock.json" ? [ file, [ "npm", "install", "--no-save", "--no-fund", "--no-audit" ] ] : [ file, argv ] }.freeze
    # What decides what installing puts in a copy, beside the steps' own files.
    LOCKS = (STEPS.map(&:first) + %w[go.sum]).freeze

    MARKER = ".sandbox-prepared".freeze
    RESTORED = ".sandbox-restored".freeze
    # Where an archived copy was, so a restored one can point what names it at its own place.
    ORIGIN = ".sandbox-origin".freeze
    # What preparing installs into the copy, kept out of git's view so a clean keeps it and a change never carries it.
    INSTALLED = [ MARKER, RESTORED, ORIGIN, "vendor/bundle", "node_modules", ".venv" ].freeze
    # What an archive of a prepared copy keeps, beside the tool versions mise installed.
    KEPT = %w[vendor/bundle node_modules .venv].freeze
    # A setup cannot move what every command needs to find its tools and its home.
    RESERVED = (INHERITED + %w[HOME LANG GIT_TERMINAL_PROMPT SANDBOX_PROGRESS]).freeze
    ENV_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    # The versions a repository asks for, through mise's shims, for everything that runs in its copy.
    def self.env(dir) = { "MISE_YES" => "1", "MISE_TRUSTED_CONFIG_PATHS" => dir, "MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS" => "ruby,node,python,go" }

    # A setup's own variables, without any the box itself sets.
    def self.setup_env(setup)
      (setup || {}).fetch("env", {}).to_h.each_with_object({}) do |(name, value), kept|
        name = name.to_s
        next unless name.match?(ENV_NAME) && !RESERVED.include?(name) && !name.start_with?("MISE_")

        kept[name] = value.to_s
      end
    end

    # The setup's services started, then its own variables over theirs, since its CI wrote them for those services.
    # Answers the variables and the services left out because the box cannot start them.
    def self.environment(dir, setup)
      started, left_out = Services.start_known((setup || {})["services"])
      [ env(dir).merge(started, setup_env(setup)), left_out ]
    end

    # Answers what it installed and ran, with the services and Postgres extensions the setup named that the box lacks,
    # so a copy prepared before still says what its tests cannot reach.
    def self.run(dir, setup = nil)
      marker = File.join(dir, MARKER)
      env, left_out = environment(dir, setup)
      lacking = { "left_out" => left_out, "missing_extensions" => Services.missing_extensions(setup) }
      return { "prepared" => [], "setup" => [], "already" => true, **lacking } if File.exist?(marker)

      exclude = File.join(dir, ".git", "info", "exclude")
      FileUtils.mkdir_p(File.dirname(exclude))
      listed = File.exist?(exclude) ? File.read(exclude).lines.map(&:strip) : []
      File.open(exclude, "a") { |file| INSTALLED.map { |path| "/#{path}" }.reject { |path| listed.include?(path) }.each { |path| file.puts(path) } }

      restored = File.exist?(File.join(dir, RESTORED))
      done = []
      (restored ? REFRESH : STEPS).each do |file, argv|
        next unless File.exist?(File.join(dir, file))
        next if argv.first == "mise" && done.any? { |step| step["command"].start_with?("mise") }

        done << step(argv, dir, env, "file" => file, "command" => argv.join(" "))
      end
      ran = []
      if done.all? { |step| step["exit_code"] == 0 }
        Array((setup || {})["commands"]).each do |command|
          ran << step([ "mise", "exec", "--", "sh", "-c", command.to_s ], dir, env, "command" => command.to_s)
          break unless ran.last["exit_code"] == 0
        end
      end
      FileUtils.touch(marker) if (done + ran).all? { |step| step["exit_code"] == 0 }
      { "prepared" => done, "setup" => ran, "restored" => restored, "already" => false, **lacking }
    end

    def self.step(argv, dir, env, said)
      result = Sandbox.run(argv, dir: dir, user: "runner", timeout: MAX_TIMEOUT, env: env)
      said.merge("exit_code" => result["exit_code"], "output" => (result["stdout"] + result["stderr"]).lines.last(40).join)
    end

    # What a copy at sha would install, as the files that decide it and the box's own tools, and whether one is prepared.
    def self.state(name, sha)
      locks = Sandbox.run!([ "git", "--git-dir", Repos.bare(name), "ls-tree", sha, "--", *LOCKS ])
      { "lock_digest" => Digest::SHA256.hexdigest([ toolchain, locks ].join("\n")),
        "prepared" => File.exist?(File.join(RUNS, "#{name}-#{sha}", MARKER)), "commit" => sha }
    end

    # The system packages and languages the image carries, which what a copy installs was built against.
    def self.toolchain
      @toolchain ||= Digest::SHA256.hexdigest([ Sandbox.run([ "dpkg-query", "-W" ])["stdout"], RUBY_DESCRIPTION,
                                                (File.read("/usr/local/go/VERSION") rescue "") ].join("\n"))
    end
  end

  # What a prepared copy installed, packed for the app to keep and handed to a later copy, in another box too, so it
  # starts with it rather than installing it all again. Packed and unpacked as runner, and only what preparing installs
  # is taken from an archive, so one cannot put anything anywhere else.
  module Archive
    MISE_INSTALLS = File.join(ENV.fetch("MISE_DATA_DIR", "/opt/mise"), "installs")
    LIMIT = 4 * 1024 * 1024 * 1024

    def self.create(name, sha)
      dir = Repos.run_copy(name, sha)
      raise Refused, "#{name} at #{sha} is not prepared, so there is nothing to keep." unless File.exist?(File.join(dir, Prepare::MARKER))

      kept = Prepare::KEPT.select { |path| File.exist?(File.join(dir, path)) }
      raise Refused, "Preparing #{name} installed nothing to keep." if kept.empty? && !File.directory?(MISE_INSTALLS)

      File.write(File.join(dir, Prepare::ORIGIN), dir)
      copy = dir.delete_prefix("/")
      paths = [ Prepare::ORIGIN, *kept ].map { |path| File.join(copy, path) }
      paths << MISE_INSTALLS.delete_prefix("/") if File.directory?(MISE_INSTALLS)
      file = File.join(RUNS, ".archive-#{SecureRandom.hex(8)}.tar.gz")
      Sandbox.run!([ "tar", "-C", "/", "-czf", file, "--transform", "s,^#{copy.gsub('.') { '\\.' }}/,copy/,S", "--", *paths ], user: "runner", timeout: MAX_TIMEOUT)
      file
    ensure
      FileUtils.rm_f(File.join(dir, Prepare::ORIGIN)) if dir
    end

    # Unpacks an archive into a staging folder and moves only what preparing installs into the copy and mise's tools,
    # then marks the copy restored so preparing runs each installer once more rather than from nothing.
    def self.restore(name, sha, file)
      dir = Repos.run_copy(name, sha)
      return { "restored" => false, "already" => true } if File.exist?(File.join(dir, Prepare::MARKER))

      staging = File.join(RUNS, ".restore-#{SecureRandom.hex(8)}")
      Sandbox.run!([ "mkdir", staging ], user: "runner")
      Sandbox.run!([ "tar", "-C", staging, "-xzf", file, "--no-same-owner", "--no-same-permissions" ], user: "runner", timeout: MAX_TIMEOUT)
      origin = File.read(File.join(staging, "copy", Prepare::ORIGIN)).strip rescue ""
      Prepare::KEPT.each do |path|
        from = File.join(staging, "copy", path)
        next unless plain?(from) && !File.exist?(File.join(dir, path))

        Sandbox.run!([ "mkdir", "-p", File.dirname(File.join(dir, path)) ], user: "runner")
        Sandbox.run!([ "mv", from, File.join(dir, path) ], user: "runner")
      end
      repoint_venv(dir, origin)
      tools = File.join(staging, MISE_INSTALLS.delete_prefix("/"))
      if plain?(tools) && File.directory?(tools)
        Sandbox.run!([ "cp", "-a", "-n", "#{tools}/.", MISE_INSTALLS ], user: "runner", timeout: MAX_TIMEOUT)
        Sandbox.run([ "mise", "reshim" ], user: "runner")
      end
      FileUtils.touch(File.join(dir, Prepare::RESTORED))
      { "restored" => true, "already" => false, "commit" => sha }
    ensure
      FileUtils.rm_rf(staging) if staging
      FileUtils.rm_f(file) if file
    end

    # Whether a path in the archive is there with no link on the way to it, so moving it moves only what was unpacked.
    def self.plain?(path) = File.exist?(path) && File.realpath(path) == File.expand_path(path)

    # A virtualenv's scripts name the copy they were installed in, so they are pointed at this one.
    def self.repoint_venv(dir, origin)
      return if origin.empty? || origin == dir

      Dir[File.join(dir, ".venv", "bin", "*")].each do |script|
        next if File.symlink?(script) || !File.file?(script)

        text = File.binread(script)
        next unless text.start_with?("#!#{origin}/")

        File.binwrite(script, text.sub("#!#{origin}/", "#!#{dir}/"))
      end
    end
  end

  # One language server per checkout and language, kept alive so the second question is fast.
  class LanguageServer
    COMMANDS = {
      "ruby" => [ "ruby-lsp" ],
      "typescript" => [ "typescript-language-server", "--stdio" ],
      "javascript" => [ "typescript-language-server", "--stdio" ],
      "go" => [ "gopls" ],
      "python" => [ "pyright-langserver", "--stdio" ]
    }.freeze
    EXTENSIONS = {
      "ruby" => %w[.rb .rake], "typescript" => %w[.ts .tsx], "javascript" => %w[.js .jsx .mjs .cjs],
      "go" => %w[.go], "python" => %w[.py]
    }.freeze
    # The Ruby server reads the repository's files but loads only its own gems, never the repository's.
    ENVIRONMENTS = { "ruby" => { "BUNDLE_GEMFILE" => "/opt/lsp/ruby/Gemfile" } }.freeze
    TSSERVER = { "tsserver" => { "path" => "/opt/tools/node_modules/typescript/lib/tsserver.js" } }.freeze
    INITIALIZATION = { "typescript" => TSSERVER, "javascript" => TSSERVER }.freeze
    INSTANCES = {}
    REPLY_TIMEOUT = 60
    # These index the whole repository after starting and answer nothing useful until they say they are done.
    INDEXING = %w[ruby go].freeze
    INDEX_TIMEOUT = 180

    def self.for(dir, language)
      raise Refused, "No language server for #{language}. There are #{COMMANDS.keys.join(', ')}." unless COMMANDS.key?(language)

      Sandbox.lock("lsp:#{dir}:#{language}") { INSTANCES["#{dir}:#{language}"] ||= new(dir, language) }
    end

    def self.language_of(path)
      EXTENSIONS.find { |_language, extensions| extensions.include?(File.extname(path)) }&.first
    end

    def initialize(dir, language)
      @dir = dir
      @language = language
      @next_id = 0
      @opened = {}
      @mutex = Mutex.new
      argv = [ "setpriv", "--reuid=runner", "--regid=runner", "--init-groups", "--", *COMMANDS.fetch(language) ]
      env = Sandbox.base_env("/home/runner").merge(ENVIRONMENTS.fetch(language, {}))
      @input, @output, @errors, @waiter = Open3.popen3(env, *argv, chdir: dir, unsetenv_others: true)
      Thread.new { @errors.each_line { } rescue nil }
      request("initialize", {
        "processId" => Process.pid, "rootUri" => uri(dir), "capabilities" => { "window" => { "workDoneProgress" => true } },
        "workspaceFolders" => [ { "uri" => uri(dir), "name" => File.basename(dir) } ], "initializationOptions" => INITIALIZATION.fetch(language, {})
      })
      notify("initialized", {})
      wait_for_index if INDEXING.include?(language)
    end

    def ask(method, path, line: nil, column: nil, query: nil)
      @mutex.synchronize do
        if method == "workspace/symbol"
          # Some servers only search the project of a file that is open, so a file naming it is opened first.
          file = file_mentioning(query.to_s)
          open_file(file) if file
          return request("workspace/symbol", { "query" => query.to_s })
        end

        open_file(path)
        params = { "textDocument" => { "uri" => uri(File.join(@dir, path)) }, "position" => { "line" => line.to_i - 1, "character" => column.to_i - 1 } }
        params["context"] = { "includeDeclaration" => true } if method == "textDocument/references"
        request(method, params)
      end
    end

    private

    def file_mentioning(text)
      patterns = EXTENSIONS.fetch(@language).map { |extension| "*#{extension}" }
      found = Sandbox.run([ "rg", "--files-with-matches", "--fixed-strings", "--max-count=1", *patterns.flat_map { |pattern| [ "--glob", pattern ] }, "--", text, "." ],
                          dir: @dir, user: "runner", timeout: 30)
      found["stdout"].lines.map { |line| line.chomp.delete_prefix("./") }.min_by(&:length)
    end

    def open_file(path)
      return if @opened[path]

      full = File.join(@dir, path)
      raise Refused, "No file #{path}" unless File.file?(full)

      notify("textDocument/didOpen", { "textDocument" => { "uri" => uri(full), "languageId" => @language, "version" => 1, "text" => File.read(full) } })
      @opened[path] = true
    end

    def uri(path) = "file://#{URI::DEFAULT_PARSER.escape(path)}"

    def notify(method, params) = write({ "jsonrpc" => "2.0", "method" => method, "params" => params })

    def request(method, params)
      id = (@next_id += 1)
      write({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
      message = pump(REPLY_TIMEOUT) { |incoming| incoming["id"] == id && !incoming.key?("method") }
      raise Refused, "The #{@language} language server did not answer #{method} in #{REPLY_TIMEOUT} seconds" unless message
      raise Refused, "#{method}: #{message.dig('error', 'message')}" if message["error"]

      message["result"]
    end

    # A server that never reports progress is asked anyway once the time is up, which is no worse than not waiting.
    def wait_for_index
      pump(INDEX_TIMEOUT) { |incoming| incoming["method"] == "$/progress" && incoming.dig("params", "value", "kind") == "end" }
    end

    # Reads until a message matches or the time is up. A server asking us something, such as its configuration, is
    # answered with nothing so it carries on.
    def pump(seconds)
      deadline = Time.now + seconds
      loop do
        remaining = deadline - Time.now
        return nil if remaining <= 0
        return nil unless IO.select([ @output ], nil, nil, remaining)

        message = read
        write({ "jsonrpc" => "2.0", "id" => message["id"], "result" => nil }) if message["method"] && message.key?("id")
        return message if yield(message)
      end
    end

    def write(message)
      body = JSON.generate(message)
      @input.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
      @input.flush
    end

    def read
      length = nil
      while (header = @output.gets("\r\n"))
        break if header == "\r\n"

        length = header.split(":", 2).last.to_i if header.downcase.start_with?("content-length")
      end
      raise Refused, "The #{@language} language server stopped" if length.nil?

      JSON.parse(@output.read(length))
    end
  end

  # A command that runs long, started in the background and read back while it runs. It is told where to write what it
  # is doing (SANDBOX_PROGRESS), which the app reads by offset as often as it likes. A reader that falls behind or goes
  # away never holds the command up, since what it writes waits on disk rather than in memory. The answer is kept for a
  # while after the command ends, so a reader that missed it can ask again.
  module Runs
    STORE = {}
    GUARD = Mutex.new
    ID = /\A\h{32}\z/
    KEPT_FOR = 15 * 60
    # The most one read hands back. A read that is full is followed at once by the next.
    CHUNK = 256 * 1024

    def self.start(request)
      sweep
      id = SecureRandom.hex(16)
      FileUtils.mkdir_p(PROGRESS, mode: 0o711)
      path = File.join(PROGRESS, "#{id}.log")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { }
      user = request["where"] == "run" ? "runner" : "reader"
      FileUtils.chown(user, user, path)
      entry = { "path" => path, "result" => nil, "finished_at" => nil }
      GUARD.synchronize { STORE[id] = entry }
      Thread.new do
        result = begin
          Handler.exec(request, progress: path)
        rescue Refused, KeyError => error
          { "error" => error.message }
        rescue StandardError => error
          { "error" => "#{error.class}: #{error.message}" }
        end
        GUARD.synchronize { entry.merge!("result" => result, "finished_at" => Time.now) }
      end
      { "id" => id }
    end

    # Whole lines from after on, and the command's answer once every line before it was read. A line longer than a
    # chunk is passed over, and the reader drops the piece of it the next read starts with.
    def self.read(id, after)
      entry = GUARD.synchronize { STORE[id] } if id.match?(ID)
      raise Refused, "No run #{id}" unless entry

      finished = GUARD.synchronize { !entry["finished_at"].nil? }
      size = File.size?(entry["path"]).to_i
      offset = after.to_i.clamp(0, size)
      data = File.open(entry["path"], "rb") { |file| file.seek(offset) && file.read([ size - offset, CHUNK ].min) }.to_s
      cut = data.rindex("\n")
      taken = if cut then cut + 1
      elsif data.bytesize == CHUNK || finished then data.bytesize
      else 0
      end
      shown = data.bytesize == CHUNK && cut.nil? ? +"" : data.byteslice(0, taken)
      more = offset + taken < size
      done = finished && !more
      { "progress" => shown.force_encoding(Encoding::UTF_8).scrub, "offset" => offset + taken, "more" => more, "done" => done,
        "result" => (GUARD.synchronize { entry["result"] } if done) }
    end

    def self.sweep
      gone = GUARD.synchronize do
        old = STORE.select { |_id, entry| entry["finished_at"] && entry["finished_at"] < Time.now - KEPT_FOR }
        old.each_key { |id| STORE.delete(id) }
        old.values
      end
      gone.each { |entry| FileUtils.rm_f(entry["path"]) }
    end
  end

  module Handler
    def self.call(method, path, body, query = {})
      case [ method, path ]
      in [ "GET", "/health" ] then { "ok" => true, "runs" => true, "setups" => true }
      in [ "PUT", %r{\A/repos/([^/]+)\z} ] then Repos.push(Regexp.last_match(1), body)
      in [ "POST", "/exec" ] then exec(JSON.parse(body))
      in [ "POST", "/runs" ] then Runs.start(JSON.parse(body))
      in [ "GET", %r{\A/runs/([^/]+)\z} ] then Runs.read(Regexp.last_match(1), query["after"])
      in [ "POST", "/prepare" ] then prepare(JSON.parse(body))
      in [ "POST", "/prepare/state" ] then state(JSON.parse(body))
      in [ "GET", "/prepare/archive" ] then Download.new(Archive.create(query.fetch("repo"), Repos.commit(query.fetch("repo"), query["ref"])))
      in [ "PUT", "/prepare/archive" ] then restore(query, body)
      in [ "POST", "/services" ] then services(JSON.parse(body))
      in [ "POST", "/lsp" ] then lsp(JSON.parse(body))
      else raise Refused, "No route #{method} #{path}"
      end
    end

    # where is "git" for a command that reads the repository's objects, "checkout" for one that reads files at a
    # commit, and "run" for one that runs in runner's writable copy. progress is the file a background command writes
    # what it is doing to.
    def self.exec(request, progress: nil)
      name = request.fetch("repo")
      sha = Repos.commit(name, request["ref"])
      argv = Array(request.fetch("argv")).map(&:to_s)
      raise Refused, "An empty command" if argv.empty?

      timeout = request.fetch("timeout", DEFAULT_TIMEOUT).to_i.clamp(1, MAX_TIMEOUT)
      told = progress ? { "SANDBOX_PROGRESS" => progress } : {}
      stdin = request["stdin"]&.to_s
      case request.fetch("where", "checkout")
      when "git"
        argv = argv.map { |part| part == "{commit}" ? sha : part }
        Sandbox.run([ "git", "--git-dir", Repos.bare(name), *argv ], user: "reader", timeout: timeout, env: told, stdin: stdin).merge("commit" => sha)
      when "checkout"
        Sandbox.run(argv, dir: Repos.checkout(name, sha), user: "reader", timeout: timeout, env: told, stdin: stdin).merge("commit" => sha)
      when "run"
        dir = Repos.run_copy(name, sha)
        env = Services.start(asked_services(request)).merge(Prepare.environment(dir, request["setup"]).first, told)
        Sandbox.run([ "mise", "exec", "--", *argv ], dir: dir, user: "runner", timeout: timeout, env: env, stdin: stdin).merge("commit" => sha)
      else raise Refused, "No place called #{request['where']}"
      end
    end

    def self.prepare(request)
      name = request.fetch("repo")
      sha = Repos.commit(name, request["ref"])
      Prepare.run(Repos.run_copy(name, sha), request["setup"]).merge("commit" => sha)
    end

    def self.restore(query, file)
      Archive.restore(query.fetch("repo"), Repos.commit(query.fetch("repo"), query["ref"]), file)
    ensure
      FileUtils.rm_f(file)
    end

    def self.state(request)
      name = request.fetch("repo")
      Prepare.state(name, Repos.commit(name, request["ref"]))
    end

    # Services started for a coding agent by name, answering the variables that reach them.
    def self.services(request)
      names = Array(request.fetch("services")).map(&:to_s)
      unknown = names - Services::KNOWN
      raise Refused, "The sandbox cannot start #{unknown.join(' or ')}. It can start #{Services::KNOWN.join(' and ')}." if unknown.any?

      { "env" => Services.start(names), "started" => names }
    end

    # A service a command names runs as the repository's setup has it, on its port and with its role, when it names it too.
    def self.asked_services(request)
      setup = Array((request["setup"] || {})["services"])
      Array(request["services"]).map { |name| setup.find { |service| service.is_a?(Hash) && service["name"] == name } || name }
    end

    def self.lsp(request)
      name = request.fetch("repo")
      sha = Repos.commit(name, request["ref"])
      dir = Repos.run_copy(name, sha)
      language = request["language"] || LanguageServer.language_of(request["path"].to_s)
      raise Refused, "Say which language to ask about" unless language

      result = LanguageServer.for(dir, language).ask(
        request.fetch("method"), request["path"].to_s, line: request["line"], column: request["column"], query: request["query"]
      )
      { "result" => result, "root" => dir, "commit" => sha }
    end
  end

  # A file the app downloads, written out as it is read and then removed.
  Download = Struct.new(:path)

  module Http
    MAX_BODY = 1024 * 1024 * 1024
    # An archive of a prepared copy is written to disk as it arrives, never held in memory.
    UPLOADS = { "/prepare/archive" => Archive::LIMIT }.freeze

    def self.serve
      server = TCPServer.new("0.0.0.0", PORT)
      $stdout.puts("sandbox listening on #{PORT}")
      loop { Thread.new(server.accept) { |socket| handle(socket) } }
    end

    def self.handle(socket)
      request_line = socket.gets("\r\n").to_s
      method, target = request_line.split(" ", 3)
      headers = {}
      while (line = socket.gets("\r\n")) && line != "\r\n"
        key, value = line.split(":", 2)
        headers[key.strip.downcase] = value.to_s.strip
      end
      return respond(socket, 401, { "error" => "Wrong key" }) unless authorized?(headers["authorization"])

      length = headers["content-length"].to_i
      path, query = target.to_s.split("?", 2)
      upload = method == "PUT" ? UPLOADS[path] : nil
      return respond(socket, 413, { "error" => "Too large" }) if length > (upload || MAX_BODY)

      body = if upload then receive(socket, length)
      else length.positive? ? socket.read(length) : ""
      end
      answer = Handler.call(method, path, body, URI.decode_www_form(query.to_s).to_h)
      answer.is_a?(Download) ? send_file(socket, answer.path) : respond(socket, 200, answer)
    rescue Refused, KeyError, JSON::ParserError => error
      respond(socket, 422, { "error" => error.message })
    rescue StandardError => error
      respond(socket, 500, { "error" => "#{error.class}: #{error.message}" })
    ensure
      socket.close unless socket.closed?
    end

    # The body copied to a file runner can read, a piece at a time.
    def self.receive(socket, length)
      file = File.join(RUNS, ".upload-#{SecureRandom.hex(8)}")
      File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0o600, binmode: true) do |out|
        left = length
        while left.positive?
          chunk = socket.read([ left, 1024 * 1024 ].min)
          raise Refused, "The upload ended early." if chunk.nil? || chunk.empty?

          out.write(chunk)
          left -= chunk.bytesize
        end
      end
      FileUtils.chown("runner", "runner", file)
      file
    end

    def self.send_file(socket, path)
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/gzip\r\nContent-Length: #{File.size(path)}\r\nConnection: close\r\n\r\n")
      File.open(path, "rb") { |file| IO.copy_stream(file, socket) }
    ensure
      FileUtils.rm_f(path)
    end

    def self.authorized?(header)
      given = header.to_s.delete_prefix("Bearer ")
      given.bytesize == KEY.bytesize && Digest::SHA256.digest(given) == Digest::SHA256.digest(KEY)
    end

    def self.respond(socket, status, payload)
      body = JSON.generate(payload)
      socket.write("HTTP/1.1 #{status} #{status == 200 ? 'OK' : 'Error'}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    end
  end
end

Sandbox::Http.serve if $PROGRAM_NAME == __FILE__
